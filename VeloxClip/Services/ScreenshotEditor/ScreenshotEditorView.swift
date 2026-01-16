import SwiftUI
import AppKit

struct ScreenshotEditorView: View {
    let image: NSImage
    let onSave: (NSImage) -> Void
    let onCopy: (NSImage) -> Void
    let onCancel: () -> Void
    
    @StateObject private var editorState = EditorState()
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @FocusState private var isTextFieldFocused: Bool
    
    // UI State
    @State private var showPropertyToolbar = false
    
    var body: some View {
        ZStack {
            // Background Layer
            Color(white: 0.1) // Much darker background for premium look
                .ignoresSafeArea()
            
            // Canvas area
            GeometryReader { geometry in
                let imageAspectRatio = image.size.width / image.size.height
                let containerAspectRatio = (geometry.size.width - 120) / (geometry.size.height - 200)
                
                let displaySize: CGSize = {
                    if imageAspectRatio > containerAspectRatio {
                        let w = geometry.size.width - 120
                        return CGSize(width: w, height: w / imageAspectRatio)
                    } else {
                        let h = geometry.size.height - 200
                        return CGSize(width: h * imageAspectRatio, height: h)
                    }
                }()
                
                let imageOrigin = CGPoint(
                    x: (geometry.size.width - displaySize.width) / 2,
                    y: (geometry.size.height - displaySize.height) / 2
                )
                
                ZStack {
                    // Image and Drawing Layer
                    ZStack {
                        // Original image with shadow
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: displaySize.width, height: displaySize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                            .position(
                                x: imageOrigin.x + displaySize.width / 2,
                                y: imageOrigin.y + displaySize.height / 2
                            )
                        
                        // Drawing canvas overlay
                        Canvas { context, size in
                            let scaleX = displaySize.width / image.size.width
                            let scaleY = displaySize.height / image.size.height
                            
                            // Draw all saved elements
                            for element in editorState.elements {
                                var transform = CGAffineTransform(translationX: imageOrigin.x, y: imageOrigin.y)
                                transform = transform.scaledBy(x: scaleX, y: scaleY)
                                
                                switch element.type {
                                case .text:
                                    if let text = element.text, let fontSize = element.fontSize {
                                        let textPoint = CGPoint(
                                            x: imageOrigin.x + element.startPoint.x * scaleX,
                                            y: imageOrigin.y + element.startPoint.y * scaleY
                                        )
                                        context.draw(
                                            Text(text)
                                                .font(.system(size: fontSize * scaleX))
                                                .foregroundColor(element.color.opacity(element.opacity)),
                                            at: textPoint
                                        )
                                    }
                                    
                                case .mosaic:
                                    if let rect = element.rect {
                                        let mosaicRect = CGRect(
                                            x: imageOrigin.x + rect.origin.x * scaleX,
                                            y: imageOrigin.y + rect.origin.y * scaleY,
                                            width: rect.width * scaleX,
                                            height: rect.height * scaleY
                                        )
                                        drawMosaicEffectInCanvas(context: context, rect: mosaicRect, imageOrigin: imageOrigin, scaleX: scaleX, scaleY: scaleY)
                                    }
                                    
                                default:
                                    if let transformedCGPath = element.path.copy(using: &transform) {
                                        let transformedPath = Path(transformedCGPath)
                                        if element.type == .highlight {
                                        context.fill(transformedPath, with: .color(element.color.opacity(element.opacity * 0.3)))
                                    } else if element.type == .arrow {
                                        context.fill(transformedPath, with: .color(element.color.opacity(element.opacity)))
                                    }
                                    context.stroke(
                                        transformedPath,
                                        with: .color(element.color.opacity(element.opacity)),
                                        lineWidth: element.lineWidth * scaleX
                                    )
                                    }
                                }
                            }
                            
                            // Draw current preview
                            if editorState.isDrawing {
                                switch editorState.currentTool {
                                case .mosaic:
                                    let rect = CGRect(
                                        x: min(editorState.startPoint.x, editorState.endPoint.x),
                                        y: min(editorState.startPoint.y, editorState.endPoint.y),
                                        width: abs(editorState.endPoint.x - editorState.startPoint.x),
                                        height: abs(editorState.endPoint.y - editorState.startPoint.y)
                                    )
                                    let previewRect = CGRect(
                                        x: imageOrigin.x + rect.origin.x * scaleX,
                                        y: imageOrigin.y + rect.origin.y * scaleY,
                                        width: rect.width * scaleX,
                                        height: rect.height * scaleY
                                    )
                                    drawMosaicEffectInCanvas(context: context, rect: previewRect, imageOrigin: imageOrigin, scaleX: scaleX, scaleY: scaleY)
                                    
                                default:
                                    if let currentPath = editorState.currentPath {
                                        var transform = CGAffineTransform(translationX: imageOrigin.x, y: imageOrigin.y)
                                        transform = transform.scaledBy(x: scaleX, y: scaleY)
                                        if let transformedCGPath = currentPath.copy(using: &transform) {
                                            let transformedPath = Path(transformedCGPath)
                                            if editorState.currentTool == .highlight {
                                                context.fill(transformedPath, with: .color(editorState.currentColor.opacity(editorState.opacity * 0.3)))
                                            } else if editorState.currentTool == .arrow {
                                                context.fill(transformedPath, with: .color(editorState.currentColor.opacity(editorState.opacity)))
                                            }
                                            context.stroke(
                                                transformedPath,
                                                with: .color(editorState.currentColor.opacity(editorState.opacity)),
                                                lineWidth: editorState.lineWidth * scaleX
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .onHover { isHovering in
                            if isHovering {
                                setCursorForTool(editorState.currentTool)
                            } else {
                                NSCursor.arrow.push()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let imageX = (value.location.x - imageOrigin.x) * (image.size.width / displaySize.width)
                                    let imageY = (value.location.y - imageOrigin.y) * (image.size.height / displaySize.height)
                                    let imagePoint = CGPoint(x: imageX, y: imageY)
                                    
                                    guard imagePoint.x >= 0 && imagePoint.x <= image.size.width &&
                                          imagePoint.y >= 0 && imagePoint.y <= image.size.height else { return }
                                    
                                    switch editorState.currentTool {
                                    case .text:
                                        if !editorState.isDrawing {
                                            editorState.textPosition = imagePoint
                                            editorState.isDrawing = true
                                        }
                                    case .eraser:
                                        editorState.eraseElements(at: imagePoint, radius: editorState.lineWidth * 2)
                                    default:
                                        if !editorState.isDrawing {
                                            editorState.startDrawing(at: imagePoint)
                                        } else {
                                            editorState.updateDrawing(to: imagePoint)
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    if editorState.currentTool != .text {
                                        editorState.finishDrawing()
                                    }
                                }
                        )
                    }
                    
                    // Floating Input Layer
                    if editorState.currentTool == .text, let textPos = editorState.textPosition, editorState.isDrawing {
                        let scaleX = displaySize.width / image.size.width
                        let scaleY = displaySize.height / image.size.height
                        let textPoint = CGPoint(
                            x: imageOrigin.x + textPos.x * scaleX,
                            y: imageOrigin.y + textPos.y * scaleY
                        )
                        
                        let fontSizeOffset = max(editorState.fontSize * scaleY, 20)
                        let inputBoxOffset = fontSizeOffset + 30
                        
                        if !editorState.textInput.isEmpty {
                            Text(editorState.textInput)
                                .font(.system(size: editorState.fontSize * scaleX))
                                .foregroundColor(editorState.currentColor.opacity(editorState.opacity))
                                .position(textPoint)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Enter text", text: $editorState.textInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: editorState.fontSize))
                                .foregroundColor(editorState.currentColor)
                                .padding(8)
                                .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(8))
                                .frame(width: 200)
                                .focused($isTextFieldFocused)
                                .onSubmit {
                                    if !editorState.textInput.isEmpty {
                                        editorState.finishDrawing()
                                    } else {
                                        editorState.textInput = ""
                                        editorState.textPosition = nil
                                        editorState.isDrawing = false
                                    }
                                }
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isTextFieldFocused = true
                                    }
                                }
                        }
                        .position(x: textPoint.x, y: textPoint.y + inputBoxOffset)
                    }
                }
            }
            
            // UI Overlay Layer
            VStack {
                // Top Action Bar
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(Circle()))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Undo/Redo Group
                        HStack(spacing: 0) {
                            Button(action: { editorState.undo() }) {
                                Image(systemName: "arrow.uturn.backward")
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .disabled(!editorState.canUndo())
                            .opacity(editorState.canUndo() ? 1 : 0.4)
                            
                            Divider().frame(height: 20).background(Color.white.opacity(0.1))
                            
                            Button(action: { editorState.redo() }) {
                                Image(systemName: "arrow.uturn.forward")
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .disabled(!editorState.canRedo())
                            .opacity(editorState.canRedo() ? 1 : 0.4)
                        }
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(10))
                        
                        Button(action: { editorState.clear() }) {
                            Image(systemName: "trash")
                                .frame(width: 40, height: 40)
                                .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                
                Spacer()
                
                // Floating Toolbar
                VStack(spacing: 16) {
                    // Property Sub-toolbar
                    if showPropertyToolbar {
                        HStack(spacing: 16) {
                            ColorPicker(editorState: editorState)
                            
                            Divider().frame(height: 24).background(Color.white.opacity(0.1))
                            
                            SizeSlider(editorState: editorState)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Main Toolbar
                    HStack(spacing: 8) {
                        // Tools
                        HStack(spacing: 4) {
                            ForEach(EditorTool.allCases) { tool in
                                ToolButton(tool: tool, currentTool: $editorState.currentTool)
                            }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.1).cornerRadius(10))
                        
                        Divider().frame(height: 32).background(Color.white.opacity(0.1))
                        
                        // Property Toggle
                        Button(action: { withAnimation(.spring(response: 0.3)) { showPropertyToolbar.toggle() } }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16))
                                .frame(width: 40, height: 40)
                                .background(showPropertyToolbar ? AnyShapeStyle(DesignSystem.primaryGradient) : AnyShapeStyle(Color.clear))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Divider().frame(height: 32).background(Color.white.opacity(0.1))
                        
                        // Action Buttons
                        Group {
                            ActionButton(icon: "square.and.arrow.down", label: "Save", color: .orange) {
                                let editedImage = renderEditedImage()
                                onSave(editedImage)
                                // We don't call onCancel() here to let the user finish the save dialog
                            }
                            
                            ActionButton(icon: "checkmark", label: "Done", color: .green) {
                                let editedImage = renderEditedImage()
                                onCopy(editedImage)
                                onCancel()
                            }
                        }
                    }
                    .padding(8)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                }
                .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
    
    // MARK: - Components
    
    struct ToolButton: View {
        let tool: EditorTool
        @Binding var currentTool: EditorTool
        
        var body: some View {
            Button(action: { currentTool = tool }) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(currentTool == tool ? AnyShapeStyle(DesignSystem.primaryGradient) : AnyShapeStyle(Color.clear))
                    .foregroundColor(currentTool == tool ? .white : .secondary)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help(tool.rawValue)
        }
    }
    
    struct ActionButton: View {
        let icon: String
        let label: String
        let color: Color
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(label).font(.system(size: 13, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(color.opacity(0.2))
                .foregroundColor(color)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }
    
    struct ColorPicker: View {
        @ObservedObject var editorState: EditorState
        var body: some View {
            HStack(spacing: 8) {
                ForEach(Array(Color.editorColors.prefix(8)), id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: editorState.currentColor == color ? 2 : 0)
                        )
                        .onTapGesture { editorState.currentColor = color }
                }
            }
        }
    }
    
    struct SizeSlider: View {
        @ObservedObject var editorState: EditorState
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: editorState.currentTool == .text ? "textformat.size" : "lineweight")
                    .foregroundColor(.secondary)
                
                Slider(value: editorState.currentTool == .text ? $editorState.fontSize : $editorState.lineWidth, in: editorState.currentTool == .text ? 6...120 : 1...30)
                    .frame(width: 120)
                    .tint(DesignSystem.primaryGradient)
                
                Text("\(Int(editorState.currentTool == .text ? editorState.fontSize : editorState.lineWidth))")
                    .font(.caption.monospaced())
                    .frame(width: 30)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func renderEditedImage() -> NSImage {
        let imageSize = image.size
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(imageSize.width),
            pixelsHigh: Int(imageSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        
        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        
        image.draw(in: NSRect(origin: .zero, size: imageSize))
        
        let context = graphicsContext.cgContext
        context.saveGState()
        
        for element in editorState.elements {
            switch element.type {
            case .text:
                if let text = element.text, let fontSize = element.fontSize {
                    let textColor = NSColor(element.color.opacity(element.opacity))
                    let font = NSFont.systemFont(ofSize: fontSize)
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                    let attributedString = NSAttributedString(string: text, attributes: attributes)
                    attributedString.draw(at: element.startPoint)
                }
            case .mosaic:
                if let rect = element.rect {
                    applyMosaicEffect(to: context, rect: rect, imageSize: imageSize)
                }
            default:
                let strokeColor = NSColor(element.color.opacity(element.opacity)).cgColor
                context.setStrokeColor(strokeColor)
                context.setLineWidth(element.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(element.path)
                
                if element.type == .highlight {
                    context.setFillColor(NSColor(element.color.opacity(element.opacity * 0.3)).cgColor)
                    context.fillPath()
                    context.addPath(element.path)
                } else if element.type == .arrow {
                    context.setFillColor(NSColor(element.color.opacity(element.opacity)).cgColor)
                    context.fillPath()
                    context.addPath(element.path)
                }
                context.strokePath()
            }
        }
        
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        
        let finalImage = NSImage(size: imageSize)
        finalImage.addRepresentation(bitmapRep)
        return finalImage
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
            pasteboard.setData(tiffData, forType: .png)
        }
    }
    
    private func drawMosaicEffectInCanvas(context: GraphicsContext, rect: CGRect, imageOrigin: CGPoint, scaleX: CGFloat, scaleY: CGFloat) {
        let imageRect = CGRect(
            x: (rect.origin.x - imageOrigin.x) / scaleX,
            y: (rect.origin.y - imageOrigin.y) / scaleY,
            width: rect.width / scaleX,
            height: rect.height / scaleY
        )
        
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let croppedRect = CGRect(
                x: max(0, imageRect.origin.x),
                y: max(0, imageRect.origin.y),
                width: min(imageRect.width, image.size.width - imageRect.origin.x),
                height: min(imageRect.height, image.size.height - imageRect.origin.y)
            )
            guard croppedRect.width > 0 && croppedRect.height > 0 else { return }
            
            if let croppedCGImage = cgImage.cropping(to: croppedRect) {
                let pixelationFactor: CGFloat = 15
                let smallSize = CGSize(width: max(1, croppedRect.width / pixelationFactor), height: max(1, croppedRect.height / pixelationFactor))
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let smallContext = CGContext(data: nil, width: Int(smallSize.width), height: Int(smallSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    smallContext.interpolationQuality = .none
                    smallContext.draw(croppedCGImage, in: CGRect(origin: .zero, size: smallSize))
                    if let pixelatedCGImage = smallContext.makeImage() {
                        context.draw(Image(nsImage: NSImage(cgImage: pixelatedCGImage, size: smallSize)).resizable().interpolation(.none), in: rect)
                    }
                }
            }
        }
    }
    
    private func applyMosaicEffect(to context: CGContext, rect: CGRect, imageSize: CGSize) {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let croppedRect = CGRect(x: max(0, rect.origin.x), y: max(0, rect.origin.y), width: min(rect.width, imageSize.width - rect.origin.x), height: min(rect.height, imageSize.height - rect.origin.y))
            guard croppedRect.width > 0 && croppedRect.height > 0 else { return }
            
            if let croppedCGImage = cgImage.cropping(to: croppedRect) {
                context.saveGState()
                let pixelationFactor: CGFloat = 15
                let smallSize = CGSize(width: max(1, croppedRect.width / pixelationFactor), height: max(1, croppedRect.height / pixelationFactor))
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let smallContext = CGContext(data: nil, width: Int(smallSize.width), height: Int(smallSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    smallContext.interpolationQuality = .none
                    smallContext.draw(croppedCGImage, in: CGRect(origin: .zero, size: smallSize))
                    if let pixelatedImage = smallContext.makeImage() {
                        context.interpolationQuality = .none
                        context.draw(pixelatedImage, in: rect)
                    }
                }
                context.restoreGState()
            }
        }
    }
    
    private func setCursorForTool(_ tool: EditorTool) {
        switch tool {
        case .pen, .arrow, .line, .rectangle, .circle, .highlight, .mosaic: NSCursor.crosshair.push()
        case .text: NSCursor.iBeam.push()
        case .eraser: NSCursor.openHand.push()
        }
    }
}


