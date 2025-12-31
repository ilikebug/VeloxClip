import SwiftUI

struct PreviewView: View {
    let item: ClipboardItem?
    @State private var debouncedItem: ClipboardItem?
    @State private var debounceTask: Task<Void, Never>?
    
    @State private var isAIProcessing = false
    @State private var aiError: String?
    @State private var showErrorDetails = false
    
    var body: some View {
        Group {
            if let item = debouncedItem {
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
                    if !item.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(item.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(tagColor(for: tag))
                                        .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .background(Color.black.opacity(0.02))
                    }
                    
                    Divider()
                    
                    ScrollView {
                        previewContent(for: item)
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
        .onChange(of: item) { newItem in
            // Cancel previous debounce task
            debounceTask?.cancel()
            
            // For small content, update immediately
            if let newItem = newItem,
               let content = newItem.content,
               content.count < 1000 && newItem.type != "image" {
                debouncedItem = newItem
                return
            }
            
            // For large content or images, debounce the update
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                if !Task.isCancelled {
                    debouncedItem = newItem
                }
            }
        }
        .onAppear {
            debouncedItem = item
        }
        .frame(minWidth: 400)
    }
    
    @ViewBuilder
    private func previewContent(for item: ClipboardItem) -> some View {
        if item.type == "image", let data = item.data {
            VStack(alignment: .leading, spacing: 12) {
                // Lazy load and scale down large images
                if let nsImage = NSImage(data: data) {
                    let maxDimension: CGFloat = 800
                    let scaledImage = resizeImage(nsImage, maxDimension: maxDimension)
                    Image(nsImage: scaledImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 500)
                } else {
                    Text("Unable to load image")
                        .foregroundColor(.secondary)
                }
                
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
            }
        } else if item.type == "color", let content = item.content {
            VStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: content) ?? .clear)
                    .frame(height: 200)
                Text(content)
                    .font(.system(.title, design: .monospaced))
            }
        } else if let content = item.content {
            // More aggressive truncation for better performance
            let maxChars = 5000
            let displayContent = content.count > maxChars ? String(content.prefix(maxChars)) : content
            
            VStack(alignment: .leading, spacing: 8) {
                // Detect if content looks like Markdown and render it
                if isMarkdown(content) {
                    MarkdownView(markdown: displayContent)
                        .textSelection(.enabled)
                } else {
                    // Plain text fallback
                    Text(displayContent)
                        .font(.body)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
                
                if content.count > maxChars {
                    Text("... (\(content.count - maxChars) more characters)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.top, 4)
                }
            }
        } else {
            Text("Preview not available for this type.")
                .foregroundColor(.secondary)
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
        
        // Show brief feedback
        print("OCR text copied to clipboard")
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
            return Color.gray
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
