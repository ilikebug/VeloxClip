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
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            toolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.95))
            
            Divider()
            
            // Canvas area
            GeometryReader { geometry in
                let imageAspectRatio = image.size.width / image.size.height
                let containerAspectRatio = geometry.size.width / geometry.size.height
                
                let displaySize: CGSize = {
                    if imageAspectRatio > containerAspectRatio {
                        // Image is wider, fit to width
                        return CGSize(
                            width: geometry.size.width,
                            height: geometry.size.width / imageAspectRatio
                        )
                    } else {
                        // Image is taller, fit to height
                        return CGSize(
                            width: geometry.size.height * imageAspectRatio,
                            height: geometry.size.height
                        )
                    }
                }()
                
                let imageOrigin = CGPoint(
                    x: (geometry.size.width - displaySize.width) / 2,
                    y: (geometry.size.height - displaySize.height) / 2
                )
                
                ZStack {
                    // Background - light gray for better visibility
                    Color(white: 0.95)
                    
                    // Image with drawings
                    ZStack {
                        // Original image
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: displaySize.width, height: displaySize.height)
                            .position(
                                x: imageOrigin.x + displaySize.width / 2,
                                y: imageOrigin.y + displaySize.height / 2
                            )
                        
                        // Drawing canvas overlay
                        Canvas { context, size in
                            // Don't draw text preview here - it will be drawn separately below
                            // Calculate scale factor for coordinate conversion
                            let scaleX = displaySize.width / image.size.width
                            let scaleY = displaySize.height / image.size.height
                            
                            // Draw all saved elements
                            for element in editorState.elements {
                                var transform = CGAffineTransform(translationX: imageOrigin.x, y: imageOrigin.y)
                                transform = transform.scaledBy(x: scaleX, y: scaleY)
                                
                                switch element.type {
                                case .text:
                                    // Draw text element
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
                                    // Draw mosaic effect
                                    if let rect = element.rect {
                                        let mosaicRect = CGRect(
                                            x: imageOrigin.x + rect.origin.x * scaleX,
                                            y: imageOrigin.y + rect.origin.y * scaleY,
                                            width: rect.width * scaleX,
                                            height: rect.height * scaleY
                                        )
                                        // Draw mosaic with actual image data
                                        drawMosaicEffectInCanvas(context: context, rect: mosaicRect, imageOrigin: imageOrigin, scaleX: scaleX, scaleY: scaleY)
                                    }
                                    
                                case .eraser:
                                    // Eraser doesn't draw, it removes elements
                                    break
                                    
                                default:
                                    // Draw path-based elements
                                    if let transformedCGPath = element.path.copy(using: &transform) {
                                        let transformedPath = Path(transformedCGPath)
                                        
                                        // Only fill for highlight tool
                                        if element.type == .highlight {
                                            context.fill(
                                                transformedPath,
                                                with: .color(element.color.opacity(element.opacity * 0.3))
                                            )
                                        }
                                        
                                        // Stroke for all tools
                                        context.stroke(
                                            transformedPath,
                                            with: .color(element.color.opacity(element.opacity)),
                                            lineWidth: element.lineWidth / scaleX
                                        )
                                    }
                                }
                            }
                            
                            // Draw current preview
                            if editorState.isDrawing {
                                switch editorState.currentTool {
                                case .text:
                                    // Text preview will be drawn separately outside Canvas
                                    break
                                    
                                case .mosaic:
                                    // Draw mosaic preview rectangle
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
                                    // Draw path-based preview
                                    if let currentPath = editorState.currentPath {
                                        var transform = CGAffineTransform(translationX: imageOrigin.x, y: imageOrigin.y)
                                        transform = transform.scaledBy(x: scaleX, y: scaleY)
                                        if let transformedCGPath = currentPath.copy(using: &transform) {
                                            let transformedPath = Path(transformedCGPath)
                                            
                                            // Only fill for highlight tool
                                            if editorState.currentTool == .highlight {
                                                context.fill(
                                                    transformedPath,
                                                    with: .color(editorState.currentColor.opacity(editorState.opacity * 0.3))
                                                )
                                            }
                                            
                                            // Stroke for all tools
                                            context.stroke(
                                                transformedPath,
                                                with: .color(editorState.currentColor.opacity(editorState.opacity)),
                                                lineWidth: editorState.lineWidth / scaleX
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
                        .onChange(of: editorState.currentTool) { _ in
                            // Update cursor when tool changes
                            setCursorForTool(editorState.currentTool)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Convert gesture location to image coordinates
                                    let imageX = (value.location.x - imageOrigin.x) * (image.size.width / displaySize.width)
                                    let imageY = (value.location.y - imageOrigin.y) * (image.size.height / displaySize.height)
                                    let imagePoint = CGPoint(x: imageX, y: imageY)
                                    
                                    // Check if point is within image bounds
                                    guard imagePoint.x >= 0 && imagePoint.x <= image.size.width &&
                                          imagePoint.y >= 0 && imagePoint.y <= image.size.height else {
                                        return
                                    }
                                    
                                    // Handle different tools
                                    switch editorState.currentTool {
                                    case .text:
                                        // Text tool: set position on tap
                                        if !editorState.isDrawing {
                                            editorState.textPosition = imagePoint
                                            editorState.isDrawing = true
                                        }
                                        
                                    case .eraser:
                                        // Eraser: remove elements at touch point
                                        editorState.eraseElements(at: imagePoint, radius: editorState.lineWidth)
                                        
                                    default:
                                        // Other tools: normal drawing
                                        if !editorState.isDrawing {
                                            editorState.startDrawing(at: imagePoint)
                                        } else {
                                            editorState.updateDrawing(to: imagePoint)
                                        }
                                    }
                                }
                                .onEnded { value in
                                    switch editorState.currentTool {
                                    case .text:
                                        // Text tool: don't finish on drag end, wait for text input
                                        // finishDrawing will be called when user submits text
                                        break
                                        
                                    default:
                                        editorState.finishDrawing()
                                    }
                                }
                        )
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    // Handle text tool tap
                                    if editorState.currentTool == .text && !editorState.isDrawing {
                                        // Text position will be set by drag gesture
                                    }
                                }
                        )
                    }
                    // Text preview and input box - outside Canvas to ensure proper layering
                    if editorState.currentTool == .text, let textPos = editorState.textPosition, editorState.isDrawing {
                        let scaleX = displaySize.width / image.size.width
                        let scaleY = displaySize.height / image.size.height
                        let textPoint = CGPoint(
                            x: imageOrigin.x + textPos.x * scaleX,
                            y: imageOrigin.y + textPos.y * scaleY
                        )
                        
                        // Calculate dynamic offset based on font size
                        // Larger font = more space needed below preview
                        let fontSizeOffset = max(editorState.fontSize * scaleY, 20)  // Minimum 20px offset
                        let inputBoxOffset = fontSizeOffset + 25  // Additional 25px spacing (increased from 10)
                        
                        // Text preview on canvas
                        if !editorState.textInput.isEmpty {
                            Text(editorState.textInput)
                                .font(.system(size: editorState.fontSize * scaleX))
                                .foregroundColor(editorState.currentColor.opacity(editorState.opacity))
                                .position(textPoint)
                        }
                        
                        // Input box below preview - position adjusts with font size
                        let inputPos = CGPoint(
                            x: imageOrigin.x + textPos.x * scaleX,
                            y: imageOrigin.y + textPos.y * scaleY + inputBoxOffset  // Dynamic offset based on font size
                        )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Enter text", text: $editorState.textInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: editorState.fontSize))
                                .foregroundColor(editorState.currentColor)
                                .padding(6)
                                .background(Color.white.opacity(0.95))
                                .cornerRadius(4)
                                .frame(width: 150)  // Fixed smaller width
                                .focused($isTextFieldFocused)
                                .onSubmit {
                                    if !editorState.textInput.isEmpty {
                                        editorState.finishDrawing()
                                    } else {
                                        // Cancel text input if empty
                                        editorState.textInput = ""
                                        editorState.textPosition = nil
                                        editorState.isDrawing = false
                                    }
                                }
                                .onAppear {
                                    // Auto-focus when input box appears
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isTextFieldFocused = true
                                    }
                                }
                            
                            // Show preview text size info
                            if !editorState.textInput.isEmpty {
                                Text("Size: \(Int(editorState.fontSize))pt")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                            }
                        }
                        .position(inputPos)
                    }
                }
            }
            
            Divider()
            
            // Bottom action bar
            actionBarView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.95))
        }
        .frame(minWidth: 1200, minHeight: 800)
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress(.return) {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                saveImage()
                return .handled
            }
            return .ignored
        }
    }
    
    private var toolbarView: some View {
        HStack(spacing: 16) {
            // Tool selection
            ForEach(EditorTool.allCases) { tool in
                Button(action: {
                    editorState.currentTool = tool
                }) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 18))
                        .foregroundColor(editorState.currentTool == tool ? .blue : .gray)
                        .frame(width: 32, height: 32)
                        .background(
                            editorState.currentTool == tool ? Color.blue.opacity(0.2) : Color.clear
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(tool.rawValue)
            }
            
            Divider()
                .frame(height: 24)
            
            // Color picker
            HStack(spacing: 8) {
                ForEach(Array(Color.editorColors.prefix(8)), id: \.self) { color in
                    Button(action: {
                        editorState.currentColor = color
                    }) {
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.blue, lineWidth: editorState.currentColor == color ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
                .frame(height: 24)
            
            // Line width / Font size slider
            HStack(spacing: 8) {
                Image(systemName: editorState.currentTool == .text ? "textformat.size" : "lineweight")
                    .foregroundColor(.gray)
                if editorState.currentTool == .text {
                    Slider(value: $editorState.fontSize, in: 6...72)
                        .frame(width: 100)
                    Text("\(Int(editorState.fontSize))")
                        .foregroundColor(.gray)
                        .frame(width: 30)
                } else {
                    Slider(value: $editorState.lineWidth, in: 1...20)
                        .frame(width: 100)
                    Text("\(Int(editorState.lineWidth))")
                        .foregroundColor(.gray)
                        .frame(width: 30)
                }
            }
            
            Spacer()
            
            // Undo/Redo
            Button(action: {
                editorState.undo()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(editorState.canUndo() ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!editorState.canUndo())
            .help("Undo (Cmd+Z)")
            
            Button(action: {
                editorState.redo()
            }) {
                Image(systemName: "arrow.uturn.forward")
                    .foregroundColor(editorState.canRedo() ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!editorState.canRedo())
            .help("Redo (Cmd+Shift+Z)")
            
            Button(action: {
                editorState.clear()
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("Clear All")
        }
    }
    
    private var actionBarView: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Button("Save") {
                saveImage()
            }
            .keyboardShortcut("s", modifiers: .command)
            
            Button("Copy") {
                copyImage()
            }
            .keyboardShortcut("c", modifiers: .command)
            
            Button("Done") {
                copyImage()
                onCancel()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
    
    private func saveImage() {
        let editedImage = renderEditedImage()
        onSave(editedImage)
    }
    
    private func copyImage() {
        let editedImage = renderEditedImage()
        onCopy(editedImage)
    }
    
    private func renderEditedImage() -> NSImage {
        let imageSize = image.size
        
        // Create bitmap representation
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
        
        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: imageSize))
        
        // Draw all elements
        let context = graphicsContext.cgContext
        context.saveGState()
        
        for element in editorState.elements {
            switch element.type {
            case .text:
                // Draw text
                if let text = element.text, let fontSize = element.fontSize {
                    let textColor = NSColor(element.color.opacity(element.opacity))
                    let font = NSFont.systemFont(ofSize: fontSize)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: textColor
                    ]
                    let attributedString = NSAttributedString(string: text, attributes: attributes)
                    attributedString.draw(at: element.startPoint)
                }
                
            case .mosaic:
                // Apply mosaic effect
                if let rect = element.rect {
                    applyMosaicEffect(to: context, rect: rect, imageSize: imageSize)
                }
                
            case .eraser:
                // Eraser doesn't render, it removes elements
                break
                
            default:
                // Draw path-based elements
                let strokeColor = NSColor(element.color.opacity(element.opacity)).cgColor
                context.setStrokeColor(strokeColor)
                context.setLineWidth(element.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                
                context.addPath(element.path)
                
                // Only fill for highlight tool
                if element.type == .highlight {
                    let fillColor = NSColor(element.color.opacity(element.opacity * 0.3)).cgColor
                    context.setFillColor(fillColor)
                    context.fillPath()
                    context.addPath(element.path) // Re-add path for stroke
                }
                
                // Stroke for all tools
                context.strokePath()
            }
        }
        
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        
        // Create final image
        let finalImage = NSImage(size: imageSize)
        finalImage.addRepresentation(bitmapRep)
        
        return finalImage
    }
    
    // MARK: - Helper Functions
    
    private func drawMosaicEffectInCanvas(context: GraphicsContext, rect: CGRect, imageOrigin: CGPoint, scaleX: CGFloat, scaleY: CGFloat) {
        // Convert display rect back to image coordinates
        let imageRect = CGRect(
            x: (rect.origin.x - imageOrigin.x) / scaleX,
            y: (rect.origin.y - imageOrigin.y) / scaleY,
            width: rect.width / scaleX,
            height: rect.height / scaleY
        )
        
        // Get the image area for mosaic
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let croppedRect = CGRect(
                x: max(0, imageRect.origin.x),
                y: max(0, imageRect.origin.y),
                width: min(imageRect.width, image.size.width - imageRect.origin.x),
                height: min(imageRect.height, image.size.height - imageRect.origin.y)
            )
            
            guard croppedRect.width > 0 && croppedRect.height > 0 else { return }
            
            if let croppedCGImage = cgImage.cropping(to: croppedRect) {
                // Create pixelated version
                let pixelationFactor: CGFloat = 15
                let smallSize = CGSize(
                    width: max(1, croppedRect.width / pixelationFactor),
                    height: max(1, croppedRect.height / pixelationFactor)
                )
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let smallContext = CGContext(
                    data: nil,
                    width: Int(smallSize.width),
                    height: Int(smallSize.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    smallContext.interpolationQuality = .none
                    smallContext.draw(croppedCGImage, in: CGRect(origin: .zero, size: smallSize))
                    
                    if let pixelatedCGImage = smallContext.makeImage() {
                        let pixelatedNSImage = NSImage(cgImage: pixelatedCGImage, size: smallSize)
                        // Draw pixelated image in Canvas
                        context.draw(
                            Image(nsImage: pixelatedNSImage)
                                .resizable()
                                .interpolation(.none),
                            in: rect
                        )
                    }
                }
            }
        }
    }
    
    private func applyMosaicEffect(to context: CGContext, rect: CGRect, imageSize: CGSize) {
        // Enhanced mosaic: pixelate the area strongly
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let croppedRect = CGRect(
                x: max(0, rect.origin.x),
                y: max(0, rect.origin.y),
                width: min(rect.width, imageSize.width - rect.origin.x),
                height: min(rect.height, imageSize.height - rect.origin.y)
            )
            
            guard croppedRect.width > 0 && croppedRect.height > 0 else { return }
            
            if let croppedCGImage = cgImage.cropping(to: croppedRect) {
                context.saveGState()
                
                // Strong pixelation: scale down significantly then scale back up
                let pixelationFactor: CGFloat = 15  // Larger factor = stronger mosaic
                let smallSize = CGSize(
                    width: max(1, croppedRect.width / pixelationFactor),
                    height: max(1, croppedRect.height / pixelationFactor)
                )
                
                // Create a small bitmap for pixelation
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let smallContext = CGContext(
                    data: nil,
                    width: Int(smallSize.width),
                    height: Int(smallSize.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    smallContext.interpolationQuality = .none
                    smallContext.draw(croppedCGImage, in: CGRect(origin: .zero, size: smallSize))
                    
                    if let pixelatedImage = smallContext.makeImage() {
                        // Draw pixelated image back at original size
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
        case .pen:
            NSCursor.crosshair.push()
        case .arrow, .line:
            NSCursor.crosshair.push()
        case .rectangle, .circle:
            NSCursor.crosshair.push()
        case .highlight:
            NSCursor.crosshair.push()
        case .text:
            NSCursor.iBeam.push()
        case .mosaic:
            NSCursor.crosshair.push()
        case .eraser:
            NSCursor.openHand.push()
        }
    }
}

