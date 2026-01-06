import SwiftUI
import Foundation

struct PreviewView: View {
    let item: ClipboardItem?
    @ObservedObject var store = ClipboardStore.shared
    @State private var debouncedItem: ClipboardItem?
    @State private var debounceTask: Task<Void, Never>?
    
    @State private var isAIProcessing = false
    @State private var aiError: String?
    @State private var showErrorDetails = false
    
    // Tag editing state
    @State private var isEditingTags = false
    @State private var newTagText = ""
    @FocusState private var isTagInputFocused: Bool
    
    // Performance optimization: Cache content type detection results
    @State private var contentTypeCache: [UUID: String] = [:]
    @State private var isContentLoading = false
    @State private var autoTagTask: Task<Void, Never>?
    
    // Get the latest item from store to ensure favorite status is up to date
    private var currentItem: ClipboardItem? {
        guard let item = item else { return nil }
        return store.items.first(where: { $0.id == item.id }) ?? item
    }
    
    var body: some View {
        Group {
            if let item = debouncedItem {
                let displayItem = currentItem ?? item
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.type.capitalized)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .kerning(1.2)
                            
                            Text(item.sourceApp ?? "System")
                                .font(.title3.bold())
                        }
                        
                        Spacer()
                        
                        // Favorite button
                        Button(action: {
                            store.toggleFavorite(for: displayItem)
                        }) {
                            Group {
                                if displayItem.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(DesignSystem.primaryGradient)
                                } else {
                                    Image(systemName: "star")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(displayItem.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        
                        
                        // AI Processing Indicator
                        if isAIProcessing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        } else if let error = aiError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                            .onTapGesture {
                                showErrorDetails = true
                            }
                            .popover(isPresented: $showErrorDetails) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("AI Service Error")
                                        .font(.headline)
                                    ScrollView {
                                        Text(error)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                    .frame(maxHeight: 300)
                                    
                                    Button("Copy Error") {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(error, forType: .string)
                                        showErrorDetails = false
                                        aiError = nil
                                    }
                                }
                                .padding()
                                .frame(width: 400)
                            }
                        }
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(item.createdAt, style: .date)
                            Text(item.createdAt, style: .time)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(DesignSystem.primaryGradient.opacity(0.1))
                    
                    // Tags Section
                    tagsSection(for: displayItem)
                    
                    Divider()
                    
                    ScrollView {
                        Group {
                            if isContentLoading {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading preview...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                previewContent(for: item)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .textSelection(.enabled)
                    
                    Divider()
                    
                    HStack {
                        Button(action: { copyToClipboard(item) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        
                        // Edit button for images
                        // Edit the original image from clipboard, not the displayed/scaled version
                        if item.type == "image", item.data != nil {
                            Button(action: {
                                // Get original image data from item - this is the raw clipboard data
                                if let imageData = item.data,
                                   let nsImage = NSImage(data: imageData) {
                                    // Use the original image data directly, not any scaled/resized version
                                    ScreenshotEditorService.shared.showEditor(with: nsImage)
                                }
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                        
                        Menu {
                            Section("AI Assistant") {
                                if let content = item.content {
                                    ForEach(AIAction.allCases) { action in
                                        Button {
                                            performAIAction(action, content: content)
                                        } label: {
                                            Label(action.rawValue, systemImage: action.icon)
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Standard Tools") {
                                // Text case transformations
                                if item.type == "text", let content = item.content {
                                    Button("UPPERCASE") {
                                        let result = AIService.shared.convertCase(content, to: .uppercase)
                                        copyTransformedText(result)
                                    }
                                    Button("lowercase") {
                                        let result = AIService.shared.convertCase(content, to: .lowercase)
                                        copyTransformedText(result)
                                    }
                                    Button("Title Case") {
                                        let result = AIService.shared.convertCase(content, to: .titleCase)
                                        copyTransformedText(result)
                                    }
                                    Button("camelCase") {
                                        let result = AIService.shared.convertCase(content, to: .camelCase)
                                        copyTransformedText(result)
                                    }
                                    Button("snake_case") {
                                        let result = AIService.shared.convertCase(content, to: .snakeCase)
                                        copyTransformedText(result)
                                    }
                                    
                                    Divider()
                                    
                                    Button("Clean Up Whitespace") {
                                        let result = AIService.shared.cleanupText(content)
                                        copyTransformedText(result)
                                    }
                                    
                                    // JSON formatting
                                    if content.contains("{") || content.contains("[") {
                                        Button("Format JSON") {
                                            if let formatted = AIService.shared.formatJSON(content) {
                                                copyTransformedText(formatted)
                                            }
                                        }
                                    }
                                    
                                    // URL extraction
                                    let urls = AIService.shared.extractURLs(from: content)
                                    if !urls.isEmpty {
                                        Button("Extract URLs (\(urls.count))") {
                                            copyTransformedText(urls.joined(separator: "\n"))
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Magic Actions", systemImage: "wand.and.stars")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        .disabled(isAIProcessing)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.black.opacity(0.02))
                }
            } else {
                ContentUnavailableView("Select an Item", systemImage: "paperclip", description: Text("Choose a clip from the history to preview its content."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: item) { _, newItem in
            // Reset editing state when switching items
            if newItem?.id != item?.id {
                isEditingTags = false
                newTagText = ""
            }
            
            // Cancel previous tasks
            debounceTask?.cancel()
            autoTagTask?.cancel()
            
            // Show loading indicator for large content
            if let newItem = newItem {
                let contentSize = newItem.content?.count ?? 0
                let isLargeContent = contentSize > 1000 || newItem.type == "image"
                isContentLoading = isLargeContent
            }
            
            // For small content, update immediately
            if let newItem = newItem,
               let content = newItem.content,
               content.count < 1000 && newItem.type != "image" {
                debouncedItem = newItem
                isContentLoading = false
                
                // Auto-add content type tag asynchronously (debounced)
                autoTagTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
                    if !Task.isCancelled {
                        await autoAddContentTypeTag(for: newItem)
                    }
                }
                return
            }
            
            // For large content or images, debounce the update
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                if !Task.isCancelled {
                    await MainActor.run {
                        debouncedItem = newItem
                        isContentLoading = false
                    }
                    
                    // Auto-add content type tag asynchronously (debounced)
                    if let newItem = newItem {
                        autoTagTask = Task {
                            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
                            if !Task.isCancelled {
                                await autoAddContentTypeTag(for: newItem)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: currentItem) { oldValue, newValue in
            // Update debounced item when favorite status changes
            if let newItem = newValue, debouncedItem?.id == newItem.id {
                debouncedItem = newItem
            }
        }
        .onAppear {
            debouncedItem = currentItem ?? item
        }
        .frame(minWidth: 400)
    }
    
    @ViewBuilder
    private func previewContent(for item: ClipboardItem) -> some View {
        if item.type == "image", let data = item.data {
            ImagePreviewView(imageData: data)
            
            // OCR Text Section - Show if OCR text exists
            if let ocrText = item.content, !ocrText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.viewfinder")
                            .foregroundColor(.blue)
                        Text("OCR Recognized Text")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            copyOCRText(ocrText)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Text")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DesignSystem.primaryGradient)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ScrollView {
                        Text(ocrText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.top, 8)
            }
        } else if item.type == "color", let content = item.content {
            ColorPreviewView(colorString: content)
        } else if item.type == "file", let content = item.content {
            FilePreviewView(filePath: content)
        } else if let content = item.content {
            // Use cached content type if available, otherwise detect and cache
            let detectedType = getOrDetectContentType(for: item, content: content)
            
            // Detect content type and show appropriate preview
            // Priority order: URL > JSON > Table > DateTime > Code > LongText > Markdown > Plain
            Group {
                switch detectedType {
                case "url":
                    VStack(alignment: .leading, spacing: 8) {
                        typeIndicator("URL")
                        URLPreviewView(urlString: content)
                    }
                case "json":
                    VStack(alignment: .leading, spacing: 8) {
                        typeIndicator("JSON")
                        JSONPreviewView(jsonString: content)
                    }
                case "table":
                    VStack(alignment: .leading, spacing: 8) {
                        typeIndicator("Table")
                        TablePreviewView(content: content)
                    }
                case "datetime":
                    VStack(alignment: .leading, spacing: 8) {
                        typeIndicator("DateTime")
                        DateTimePreviewView(dateString: content)
                    }
                case "code":
                    VStack(alignment: .leading, spacing: 8) {
                        typeIndicator("Code")
                        CodePreviewView(code: content)
                    }
                case "longtext":
                    VStack(alignment: .leading, spacing: 8) {
                        typeIndicator("LongText")
                        TextSummaryView(text: content)
                    }
                case "markdown":
                    let maxChars = 5000
                    let displayContent = content.count > maxChars ? String(content.prefix(maxChars)) : content
                    
                    VStack(alignment: .leading, spacing: 8) {
                        typeIndicator("Markdown")
                        MarkdownView(markdown: displayContent)
                            .textSelection(.enabled)
                        
                        if content.count > maxChars {
                            Text("... (\(content.count - maxChars) more characters)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.top, 4)
                        }
                    }
                default:
                    // Plain text fallback
                    let maxChars = 5000
                    let displayContent = content.count > maxChars ? String(content.prefix(maxChars)) : content
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayContent)
                            .font(.body)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                        
                        if content.count > maxChars {
                            Text("... (\(content.count - maxChars) more characters)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.top, 4)
                        }
                    }
                }
            }
        } else {
            Text("Preview not available for this type.")
                .foregroundColor(.secondary)
        }
    }
    
    // Get cached content type or detect and cache it
    private func getOrDetectContentType(for item: ClipboardItem, content: String) -> String {
        if let cached = contentTypeCache[item.id] {
            return cached
        } else {
            let detected = detectContentType(content)
            contentTypeCache[item.id] = detected
            return detected
        }
    }
    
    // Get cached content type or return nil
    private func getCachedContentType(for item: ClipboardItem) -> String? {
        return contentTypeCache[item.id]
    }
    
    // Detect content type with optimized priority order
    private func detectContentType(_ content: String) -> String {
        // Fast checks first (single line checks)
        if isURL(content) {
            return "url"
        }
        
        // Then check for structured data
        if isJSON(content) {
            return "json"
        }
        
        if isTableData(content) {
            return "table"
        }
        
        // Short content checks
        if isDateTime(content) {
            return "datetime"
        }
        
        // Code detection (requires scanning)
        if isCode(content) {
            return "code"
        }
        
        // Long text check
        if isLongText(content) {
            return "longtext"
        }
        
        // Markdown detection (requires regex)
        if isMarkdown(content) {
            return "markdown"
        }
        
        return "plain"
    }
    
    // Content type detection helpers
    private func isJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else { return false }
        
        // Check if starts with { or [ and ends with } or ]
        let startsWithBrace = trimmed.first == "{" || trimmed.first == "["
        let endsWithBrace = trimmed.last == "}" || trimmed.last == "]"
        
        guard startsWithBrace && endsWithBrace else { return false }
        
        // Try to parse as JSON to verify
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
    
    private func isURL(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must be a single line and start with http/https/ftp/file
        // Also check if it's a valid URL format
        guard trimmed.components(separatedBy: .newlines).count == 1 else { return false }
        
        // Check for URL prefixes
        let hasURLPrefix = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
                          trimmed.hasPrefix("ftp://") || trimmed.hasPrefix("file://")
        
        if hasURLPrefix {
            // Verify it's a valid URL
            return URL(string: trimmed) != nil
        }
        
        return false
    }
    
    private func isCode(_ content: String) -> Bool {
        // Check for common code patterns - need multiple indicators to avoid false positives
        let codeIndicators = [
            "func ", "class ", "def ", "import ", "const ", "let ", "var ",
            "function ", "=>", "->", "public ", "private ", "#include",
            "<?php", "<script", "SELECT ", "FROM ", "WHERE ", "namespace ",
            "interface ", "extends ", "implements ", "async ", "await "
        ]
        
        let matchCount = codeIndicators.filter { content.contains($0) }.count
        // Need at least 2 indicators to be considered code
        return matchCount >= 2
    }
    
    private func isTableData(_ content: String) -> Bool {
        // Check if content looks like CSV/TSV
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        guard lines.count >= 2 else { return false }
        
        // Check first few lines for consistent delimiter usage
        let firstLine = lines[0]
        let commaCount = firstLine.components(separatedBy: ",").count
        let tabCount = firstLine.components(separatedBy: "\t").count
        let pipeCount = firstLine.components(separatedBy: "|").count
        
        // Need at least 2 columns
        guard commaCount >= 2 || tabCount >= 2 || pipeCount >= 2 else { return false }
        
        // Check if at least 2 lines have similar structure
        let delimiter = commaCount >= 2 ? "," : (tabCount >= 2 ? "\t" : "|")
        let expectedColumns = delimiter == "," ? commaCount : (delimiter == "\t" ? tabCount : pipeCount)
        
        let consistentLines = lines.prefix(5).filter { line in
            let count = line.components(separatedBy: delimiter).count
            return count == expectedColumns || abs(count - expectedColumns) <= 1
        }
        
        return consistentLines.count >= 2
    }
    
    private func isDateTime(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must be relatively short (date/time strings are usually short)
        guard trimmed.count < 100 else { return false }
        
        // Check for common date/time patterns
        let patterns = [
            #"^\d{4}-\d{2}-\d{2}$"#,                    // YYYY-MM-DD
            #"^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}"#,       // YYYY-MM-DD HH:MM
            #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#,         // ISO format
            #"^\d{2}/\d{2}/\d{4}$"#,                    // MM/DD/YYYY
            #"^\d{10}$"#,                                // Unix timestamp (seconds)
            #"^\d{13}$"#                                 // Unix timestamp (milliseconds)
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }
        return false
    }
    
    private func isLongText(_ content: String) -> Bool {
        // Long text: more than 500 characters and multiple paragraphs
        return content.count > 500 && content.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count > 2
    }
    
    // Debug helper to show detected type
    @ViewBuilder
    private func typeIndicator(_ type: String) -> some View {
        HStack {
            Text("Preview Type: \(type)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            Spacer()
        }
    }
    
    // Helper to resize large images
    private func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let maxSize = max(size.width, size.height)
        
        if maxSize <= maxDimension {
            return image
        }
        
        let scale = maxDimension / maxSize
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        
        // Use modern API instead of deprecated lockFocus/unlockFocus
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        
        // Create a new CGImage with the desired size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }
        
        // Set high quality interpolation
        context.interpolationQuality = .high
        
        // Draw the image scaled to new size
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
        
        guard let resizedCGImage = context.makeImage() else {
            return image
        }
        
        // Create NSImage from CGImage
        let newImage = NSImage(cgImage: resizedCGImage, size: newSize)
        return newImage
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Priority 1: If it's an image, copy the binary data
        if item.type == "image", let data = item.data {
            // Write multiple formats to ensure compatibility with all apps
            pasteboard.setData(data, forType: .tiff)
            pasteboard.setData(data, forType: .png) 
            return
        }
        
        // Priority 2: If it's a color, copy the hex string
        if item.type == "color", let content = item.content {
            pasteboard.setString(content, forType: .string)
            return
        }
        
        // Priority 3: Fallback to general content or data
        if let content = item.content {
            pasteboard.setString(content, forType: .string)
        } else if let data = item.data {
            if item.type == "rtf" {
                pasteboard.setData(data, forType: .rtf)
            }
        }
    }
    
    private func performAIAction(_ action: AIAction, content: String) {
        isAIProcessing = true
        aiError = nil
        
        Task {
            do {
                let result = try await LLMService.shared.performAction(action, content: content)
                copyTransformedText(result)
                
                // Show completion feedback
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s pause to show "done"
                
            } catch {
                // Use unified error handler
                ErrorHandler.shared.handle(error)
                // Also show in preview for immediate feedback
                aiError = "AI Service Failed: \(error.localizedDescription)"
            }
            isAIProcessing = false
        }
    }
    
    private func copyOCRText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func copyTransformedText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func tagColor(for tag: String) -> Color {
        switch tag.uppercased() {
        case "OCR":
            return Color.purple
        case "URL":
            return Color.blue
        case "EMAIL":
            return Color.cyan
        case "CODE":
            return Color.green
        case "JSON":
            return Color.mint
        case "PHONE":
            return Color.orange
        default:
            // Generate a colorful background for custom tags based on tag name
            return generateColorFromString(tag)
        }
    }
    
    // Generate a consistent vibrant color from a string (for custom tags)
    private func generateColorFromString(_ string: String) -> Color {
        // Use hash to generate consistent color for same tag name
        var hash = 0
        for char in string.utf8 {
            hash = Int(char) &+ (hash << 6) &+ (hash << 16) &- hash
        }
        
        // Generate vibrant colors using HSB (Hue, Saturation, Brightness)
        // Hue: 0-360 degrees, map to 0.0-1.0
        let hue = Double(abs(hash) % 360) / 360.0
        // Saturation: 0.6-0.9 for vibrant colors
        let saturation = 0.6 + (Double(abs(hash / 7) % 30) / 100.0)
        // Brightness: 0.5-0.7 for good contrast
        let brightness = 0.5 + (Double(abs(hash / 13) % 20) / 100.0)
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    // Determine text color based on background color brightness
    private func textColor(for tag: String) -> Color {
        // For system tags, always use white
        switch tag.uppercased() {
        case "OCR", "URL", "EMAIL", "CODE", "JSON", "PHONE":
            return .white
        default:
            // For custom tags, check brightness to determine text color
            var hash = 0
            for char in tag.utf8 {
                hash = Int(char) &+ (hash << 6) &+ (hash << 16) &- hash
            }
            // Brightness range: 0.5-0.7, use white for darker colors (< 0.65), black for lighter
            let brightness = 0.5 + (Double(abs(hash / 13) % 20) / 100.0)
            return brightness > 0.65 ? .black : .white
        }
    }
    
    @ViewBuilder
    private func tagsSection(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Edit button (only show for favorite items)
                if item.isFavorite {
                    Button(action: {
                        isEditingTags.toggle()
                        if isEditingTags {
                            isTagInputFocused = true
                        }
                    }) {
                        Image(systemName: isEditingTags ? "checkmark.circle.fill" : "pencil.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(item.tags, id: \.self) { tag in
                        let bgColor = tagColor(for: tag)
                        let txtColor = textColor(for: tag)
                        
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption.bold())
                                .foregroundColor(txtColor)
                            
                            // Delete button (only show when editing)
                            if isEditingTags && item.isFavorite {
                                Button(action: {
                                    removeTag(tag, from: item)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(txtColor.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(bgColor)
                        .cornerRadius(6)
                    }
                    
                    // Add tag input (only show when editing)
                    if isEditingTags && item.isFavorite {
                        HStack(spacing: 4) {
                            TextField("Add tag", text: $newTagText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .focused($isTagInputFocused)
                                .frame(width: 80)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                                .onSubmit {
                                    addTag(from: item)
                                }
                            
                            Button(action: {
                                addTag(from: item)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newTagText.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(Color.black.opacity(0.02))
    }
    
    private func addTag(from item: ClipboardItem) {
        let trimmedTag = newTagText.trimmingCharacters(in: CharacterSet.whitespaces)
        guard !trimmedTag.isEmpty else { return }
        
        var updatedTags = item.tags
        if !updatedTags.contains(trimmedTag) {
            updatedTags.append(trimmedTag)
            store.updateTags(id: item.id, tags: updatedTags)
        }
        
        newTagText = ""
    }
    
    private func removeTag(_ tag: String, from item: ClipboardItem) {
        var updatedTags = item.tags
        updatedTags.removeAll(where: { $0 == tag })
        store.updateTags(id: item.id, tags: updatedTags)
    }
    
    // Auto-add content type tag based on detected content type (async, optimized)
    private func autoAddContentTypeTag(for item: ClipboardItem) async {
        // Only auto-tag favorite items
        guard item.isFavorite else { return }
        
        // Use cached content type if available
        let detectedType: String?
        if let cachedType = contentTypeCache[item.id] {
            detectedType = cachedType
        } else {
            // Check item type first
            switch item.type.lowercased() {
            case "image":
                detectedType = "image"
            case "file":
                detectedType = "file"
            case "color":
                detectedType = "color"
            default:
                // Detect content type for text items
                if let content = item.content {
                    detectedType = detectContentType(content)
                } else {
                    detectedType = nil
                }
            }
        }
        
        // Add tag if detected and not already present
        if let tag = detectedType, tag != "plain" {
            var updatedTags = item.tags
            let lowercasedTag = tag.lowercased()
            
            // Check if tag already exists (case-insensitive)
            let tagExists = updatedTags.contains { $0.lowercased() == lowercasedTag }
            
            if !tagExists {
                updatedTags.append(tag)
                await MainActor.run {
                    store.updateTags(id: item.id, tags: updatedTags)
                }
            }
        }
    }
    
    // Detect if content looks like Markdown
    private func isMarkdown(_ content: String) -> Bool {
        // Check for common Markdown patterns
        let markdownPatterns = [
            #"^#{1,6}\s+"#,                    // Headers (# ## ###)
            #"\*\*.*?\*\*"#,                    // Bold **text**
            #"_.*?_"#,                          // Italic _text_
            #"`.*?`"#,                          // Inline code `code`
            #"```[\s\S]*?```"#,                // Code blocks
            #"^\s*[-*+]\s+"#,                  // Unordered lists
            #"^\s*\d+\.\s+"#,                  // Ordered lists
            #"^\s*>\s+"#,                      // Blockquotes
            #"\[.*?\]\(.*?\)"#,                // Links [text](url)
            #"^\s*\|.*\|"#,                    // Tables
        ]
        
        for pattern in markdownPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]),
               regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                return true
            }
        }
        
        return false
    }
}

// Utility View for Blur Effect
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Extension for Hex Colors
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        var r: Double = 0.0
        var g: Double = 0.0
        var b: Double = 0.0
        var a: Double = 1.0
        
        let length = hexSanitized.count
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        if length == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
