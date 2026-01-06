import AppKit
import Combine

@MainActor
class ClipboardMonitor: ObservableObject {
    private var timer: AnyCancellable?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    
    init() {
        self.lastChangeCount = pasteboard.changeCount
        startMonitoring()
    }
    
    private func startMonitoring() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkForChanges()
            }
    }
    
    private func checkForChanges() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        processClippedContent()
    }
    
    private func processClippedContent() {
        // Find the source application
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let sourceApp = frontmostApp?.localizedName
        let bundleID = frontmostApp?.bundleIdentifier
        
        // Check blacklist
        if BlacklistManager.shared.shouldIgnore(bundleID: bundleID) {
            return
        }
        
        // Extract data immediately on main thread to avoid pasteboard state changes
        let stringContent = pasteboard.string(forType: .string)
        let rtfData = pasteboard.data(forType: .rtf)
        let tiffData = pasteboard.data(forType: .tiff)
        let pngData = pasteboard.data(forType: .png)
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        
        Task.detached(priority: .userInitiated) {
            // 1. Check for Text
            if let text = stringContent {
                if self.isColor(text) {
                    await self.saveItemAsync(type: "color", content: text, sourceApp: sourceApp)
                } else {
                    await self.saveItemAsync(type: "text", content: text, sourceApp: sourceApp)
                }
            }
            // 2. Check for RTF
            else if let data = rtfData {
                await self.saveItemAsync(type: "rtf", data: data, sourceApp: sourceApp)
            }
            // 3. Check for Images
            else if let imageData = tiffData ?? pngData {
                let newItem = await self.saveItemAsync(type: "image", data: imageData, sourceApp: sourceApp)
                
                // Perform OCR in background
                let itemID = newItem.id
                AIService.shared.performOCR(on: imageData) { text in
                    if let text = text, !text.isEmpty {
                        Task { @MainActor in
                            if ClipboardStore.shared.items.contains(where: { $0.id == itemID }) {
                                ClipboardStore.shared.updateItem(id: itemID, content: text)
                            }
                        }
                    }
                }
            }
            // 4. Check for Files
            else if let urls = fileURLs, !urls.isEmpty {
                let paths = urls.map { $0.path }.joined(separator: "\n")
                await self.saveItemAsync(type: "file", content: paths, sourceApp: sourceApp)
            }
        }
    }
    
    @discardableResult
    private func saveItemAsync(type: String, content: String? = nil, data: Data? = nil, sourceApp: String? = nil) async -> ClipboardItem {
        // Deduplication check on MainActor
        return await MainActor.run {
            let now = Date()
            let recentItemsSnapshot = Array(ClipboardStore.shared.items.prefix(10))
            
            for recentItem in recentItemsSnapshot {
                if recentItem.type == type && recentItem.content == content && recentItem.data == data {
                    let timeDiff = now.timeIntervalSince(recentItem.createdAt)
                    if timeDiff < 5.0 { return recentItem }
                }
            }
            
            let newItem = ClipboardItem(type: type, content: content, data: data, sourceApp: sourceApp)
            
            // Heavy background analysis
            let capturedContent = content // Capturing for the task below
            let capturedNewItem = newItem
            
            Task.detached(priority: .background) {
                var analyzedItem = capturedNewItem
                if let text = capturedContent {
                    analyzedItem.tags = self.detectTags(in: text)
                    
                    if text.count >= 3 && text.count <= 2000 {
                        if let vector = await AIService.shared.generateEmbedding(for: text) {
                            if let vectorData = try? JSONEncoder().encode(vector) {
                                analyzedItem.embedding = vectorData
                            }
                        }
                    }
                    
                    // Update item with tags and embedding if changed
                    if !analyzedItem.tags.isEmpty || analyzedItem.embedding != nil {
                        await MainActor.run {
                            // Potentially add a method to update tags/embedding in batch
                            ClipboardStore.shared.updateTags(id: analyzedItem.id, tags: analyzedItem.tags)
                            // Note: updateTags currently only updates tags, we might need an updateMetadata
                            // For simplicity, let's just make sure the initial addItem has what we can get quickly
                        }
                    }
                }
            }
            
            ClipboardStore.shared.addItem(newItem)
            return newItem
        }
    }
    
    private func updateItemContent(id: UUID, content: String) {
        ClipboardStore.shared.updateItem(id: id, content: content)
    }
    
    nonisolated private func detectTags(in text: String) -> [String] {
        var tags: [String] = []
        
        // URL detection
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if !matches.isEmpty {
                tags.append("URL")
            }
        }
        
        // Email detection
        if text.contains("@") && text.contains(".") {
            let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            if let _ = text.range(of: emailPattern, options: .regularExpression) {
                tags.append("Email")
            }
        }
        
        // Phone number detection (simple pattern)
        let phonePattern = "\\b\\d{3}[-.]?\\d{3,4}[-.]?\\d{4}\\b"
        if let _ = text.range(of: phonePattern, options: .regularExpression) {
            tags.append("Phone")
        }
        
        // Code detection (contains common programming keywords or symbols)
        let codeIndicators = ["func ", "class ", "def ", "import ", "const ", "let ", "var ", "function ", "=>", "->", "public ", "private "]
        if codeIndicators.contains(where: { text.contains($0) }) {
            tags.append("Code")
        }
        
        // JSON detection
        if (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]")) {
            if let _ = try? JSONSerialization.jsonObject(with: Data(text.utf8)) {
                tags.append("JSON")
            }
        }
        
        return tags
    }
    
    nonisolated private func isColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexPattern = "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3}|[A-Fa-f0-9]{8})$"
        let rgbPattern = #"^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$"#
        
        return trimmed.range(of: hexPattern, options: .regularExpression) != nil ||
               trimmed.range(of: rgbPattern, options: .regularExpression) != nil
    }
}
