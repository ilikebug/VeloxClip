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
            print("Ignoring clipboard change from blacklisted app: \(sourceApp ?? "Unknown")")
            return
        }
        
        // 1. Check for Text
        if let text = pasteboard.string(forType: .string) {
            if isHexColor(text) {
                saveItem(type: "color", content: text, sourceApp: sourceApp)
            } else {
                saveItem(type: "text", content: text, sourceApp: sourceApp)
            }
        }
        // 2. Check for RTF
        else if let rtfData = pasteboard.data(forType: .rtf) {
            saveItem(type: "rtf", data: rtfData, sourceApp: sourceApp)
        }
        // 3. Check for Images
        else if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            let newItem = saveItem(type: "image", data: imageData, sourceApp: sourceApp)
            
            // Perform OCR in background
            // Store item ID to ensure we can update it even if it's moved in the list
            let itemID = newItem.id
            AIService.shared.performOCR(on: imageData) { [weak self] text in
                if let text = text, !text.isEmpty {
                    Task { @MainActor in
                        // Find the item by ID (in case list order changed)
                        if ClipboardStore.shared.items.contains(where: { $0.id == itemID }) {
                            self?.updateItemContent(id: itemID, content: text)
                        }
                    }
                }
            }
        }
        // 4. Check for Files
        else if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            let paths = fileURLs.map { $0.path }.joined(separator: "\n")
            saveItem(type: "file", content: paths, sourceApp: sourceApp)
        }
    }
    
    @discardableResult
    private func saveItem(type: String, content: String? = nil, data: Data? = nil, sourceApp: String? = nil) -> ClipboardItem {
        // Improved deduplication: Check recent items (last 10) within 5 seconds
        // Create a snapshot to avoid concurrent modification issues
        let now = Date()
        let recentItemsSnapshot = Array(ClipboardStore.shared.items.prefix(10))
        
        for recentItem in recentItemsSnapshot {
            // Check if content matches
            let contentMatches = recentItem.content == content
            let dataMatches = recentItem.data == data
            let typeMatches = recentItem.type == type
            
            // Check if within 5 seconds
            let timeDiff = now.timeIntervalSince(recentItem.createdAt)
            
            if typeMatches && contentMatches && dataMatches && timeDiff < 5.0 {
                // Duplicate found, return existing item
                return recentItem
            }
        }
        
        var newItem = ClipboardItem(type: type, content: content, data: data, sourceApp: sourceApp)
        
        // Auto-tagging based on content analysis
        if let text = content {
            newItem.tags = detectTags(in: text)
            
            // Generate semantic embedding for text content
            // Only generate for text that's not too short or too long
            if text.count >= 3 && text.count <= 2000 {
                if let vector = AIService.shared.generateEmbedding(for: text) {
                    if let vectorData = try? JSONEncoder().encode(vector) {
                        newItem.embedding = vectorData
                    }
                }
            }
        }
        
        ClipboardStore.shared.addItem(newItem)
        return newItem
    }
    
    // Helper to update an item in the store (since it's a struct/value type)
    private func updateItemContent(id: UUID, content: String) {
        ClipboardStore.shared.updateItem(id: id, content: content)
    }
    
    private func detectTags(in text: String) -> [String] {
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
    
    private func isHexColor(_ text: String) -> Bool {
        let pattern = "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
