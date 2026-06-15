import SwiftUI
import AppKit

struct ScreenshotEditorView: View {
    let image: NSImage
    @ObservedObject var editorState: EditorState
    let onSave: (NSImage) -> Void
    let onDone: (NSImage) -> Void
    let onClose: () -> Void

    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @FocusState private var isTextFieldFocused: Bool
    
    // UI State
    @State private var showPropertyToolbar = false
    
    // Local text editing state (doesn't trigger Canvas redraw)
    @State private var editingText: String = ""
    
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
                        .drawingGroup()  // Render Canvas to offscreen buffer to prevent redraws
                        .onHover { isHovering in
                            // Use set() instead of push() — push grows the cursor stack on every hover
                            if isHovering {
                                setCursorForTool(editorState.currentTool)
                            } else {
                                NSCursor.arrow.set()
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
                                            editingText = ""  // Reset local text
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
                                    switch editorState.currentTool {
                                    case .text:
                                        break
                                    case .eraser:
                                        // One undo step per drag, not per erased element
                                        editorState.endEraseSession()
                                    default:
                                        editorState.finishDrawing()
                                    }
                                }
                        )
                    }
                    
                    // Floating Input Layer - isolated component
                    if editorState.currentTool == .text, let textPos = editorState.textPosition, editorState.isDrawing {
                        FloatingTextInput(
                            textPos: textPos,
                            editingText: $editingText,
                            imageOrigin: imageOrigin,
                            displaySize: displaySize,
                            imageSize: image.size,
                            fontSize: editorState.fontSize,
                            textColor: editorState.currentColor,
                            opacity: editorState.opacity,
                            isTextFieldFocused: $isTextFieldFocused,
                            onDragEnded: { deltaX, deltaY in
                                let newX = textPos.x + deltaX
                                let newY = textPos.y + deltaY
                                let clampedX = max(0, min(image.size.width, newX))
                                let clampedY = max(0, min(image.size.height, newY))
                                editorState.textPosition = CGPoint(x: clampedX, y: clampedY)
                            },
                            onSubmit: {
                                if !editingText.isEmpty {
                                    editorState.textInput = editingText
                                    editorState.finishDrawing()
                                    editingText = ""
                                } else {
                                    editorState.textInput = ""
                                    editorState.textPosition = nil
                                    editorState.isDrawing = false
                                    editingText = ""
                                }
                            }
                        )
                    }
                }
            }
            
            // UI Overlay Layer
            VStack {
                // Top Action Bar
                HStack {
                    Button(action: onClose) {
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

                            Divider().frame(height: 24).background(Color.white.opacity(0.1))

                            OpacitySlider(editorState: editorState)
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
                                onDone(editedImage)
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
        .frame(minWidth: 880, minHeight: 600)
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
                
                DSSlider(value: editorState.currentTool == .text ? $editorState.fontSize : $editorState.lineWidth, in: editorState.currentTool == .text ? 6...120 : 1...30)
                    .frame(width: 120)

                Text("\(Int(editorState.currentTool == .text ? editorState.fontSize : editorState.lineWidth))")
                    .font(.dsCaption.monospaced())
                    .frame(width: 30)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    struct OpacitySlider: View {
        @ObservedObject var editorState: EditorState
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundColor(.secondary)

                DSSlider(value: $editorState.opacity, in: 0.1...1.0)
                    .frame(width: 100)

                Text("\(Int(editorState.opacity * 100))%")
                    .font(.dsCaption.monospaced())
                    .frame(width: 40)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func renderEditedImage() -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        // image.size is in points; Retina screenshots carry 2x pixels. Size the bitmap
        // by true pixel dimensions or the export loses half its resolution.
        let repPixelsWide = image.representations.map(\.pixelsWide).max() ?? 0
        let repPixelsHigh = image.representations.map(\.pixelsHigh).max() ?? 0
        let pixelsWide = repPixelsWide > 0 ? repPixelsWide : Int(imageSize.width)
        let pixelsHigh = repPixelsHigh > 0 ? repPixelsHigh : Int(imageSize.height)

        // Bitmap/context creation can fail on extreme dimensions or memory pressure —
        // fall back to the unedited image instead of crashing on a force unwrap
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            print("❌ Failed to create bitmap context for edited image, returning original")
            return image
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let context = graphicsContext.cgContext

        // Map user space to points so all drawing below (image, annotations,
        // line widths, font sizes) lands on the full pixel raster
        context.saveGState()
        context.scaleBy(x: CGFloat(pixelsWide) / imageSize.width, y: CGFloat(pixelsHigh) / imageSize.height)

        image.draw(in: NSRect(origin: .zero, size: imageSize))

        context.saveGState()

        // Flip coordinate system: SwiftUI uses top-down (Y=0 at top), Core Graphics uses bottom-up (Y=0 at bottom)
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        for element in editorState.elements {
            switch element.type {
            case .text:
                if let text = element.text, let fontSize = element.fontSize {
                    // Text rendering requires special handling
                    context.saveGState()
                    
                    // Move to text position
                    context.translateBy(x: element.startPoint.x, y: element.startPoint.y)
                    // Flip back so text appears right-side up
                    context.scaleBy(x: 1.0, y: -1.0)
                    
                    let textColor = NSColor(element.color.opacity(element.opacity))
                    let font = NSFont.systemFont(ofSize: fontSize)
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                    let attributedString = NSAttributedString(string: text, attributes: attributes)
                    // Canvas preview centers text on its point — anchor the export the same way
                    let textSize = attributedString.size()
                    attributedString.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))

                    context.restoreGState()
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
        
        context.restoreGState() // flip
        context.restoreGState() // points→pixels scale
        NSGraphicsContext.restoreGraphicsState()

        // Report the rep in points so the NSImage keeps its 2x backing scale
        bitmapRep.size = imageSize
        let finalImage = NSImage(size: imageSize)
        finalImage.addRepresentation(bitmapRep)
        return finalImage
    }
    
    // Pixelates the source region under `pointRect` (top-down, point coordinates).
    // CGImage cropping operates on bitmap rows (top-left origin) in PIXELS — on Retina
    // the backing CGImage is 2x the point size, so the rect must be scaled before cropping.
    private func pixelatedPatch(forPointRect pointRect: CGRect) -> CGImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let clamped = pointRect.intersection(CGRect(origin: .zero, size: image.size))
        guard clamped.width > 0, clamped.height > 0 else { return nil }

        let pxScaleX = CGFloat(cgImage.width) / image.size.width
        let pxScaleY = CGFloat(cgImage.height) / image.size.height
        let cropRect = CGRect(
            x: clamped.origin.x * pxScaleX,
            y: clamped.origin.y * pxScaleY,
            width: clamped.width * pxScaleX,
            height: clamped.height * pxScaleY
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        let pixelationFactor: CGFloat = 15
        let smallSize = CGSize(
            width: max(1, clamped.width / pixelationFactor),
            height: max(1, clamped.height / pixelationFactor)
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let smallContext = CGContext(data: nil, width: Int(smallSize.width), height: Int(smallSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        smallContext.interpolationQuality = .none
        smallContext.draw(croppedCGImage, in: CGRect(origin: .zero, size: smallSize))
        return smallContext.makeImage()
    }

    private func drawMosaicEffectInCanvas(context: GraphicsContext, rect: CGRect, imageOrigin: CGPoint, scaleX: CGFloat, scaleY: CGFloat) {
        let imageRect = CGRect(
            x: (rect.origin.x - imageOrigin.x) / scaleX,
            y: (rect.origin.y - imageOrigin.y) / scaleY,
            width: rect.width / scaleX,
            height: rect.height / scaleY
        )

        if let pixelatedCGImage = pixelatedPatch(forPointRect: imageRect) {
            let patchSize = CGSize(width: pixelatedCGImage.width, height: pixelatedCGImage.height)
            context.draw(Image(nsImage: NSImage(cgImage: pixelatedCGImage, size: patchSize)).resizable().interpolation(.none), in: rect)
        }
    }

    private func applyMosaicEffect(to context: CGContext, rect: CGRect, imageSize: CGSize) {
        // rect is top-down (same space the user drew in) — pixelatedPatch handles cropping
        guard let pixelatedImage = pixelatedPatch(forPointRect: rect) else { return }

        context.saveGState()
        context.interpolationQuality = .none
        // The export context is flipped to top-down; CGContext.draw renders images
        // bottom-up, so mirror around the rect's center to keep the patch upright
        context.translateBy(x: 0, y: rect.midY)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: 0, y: -rect.midY)
        context.draw(pixelatedImage, in: rect)
        context.restoreGState()
    }
    
    private func setCursorForTool(_ tool: EditorTool) {
        switch tool {
        case .pen, .arrow, .line, .rectangle, .circle, .highlight, .mosaic: NSCursor.crosshair.set()
        case .text: NSCursor.iBeam.set()
        case .eraser: NSCursor.openHand.set()
        }
    }
}

// MARK: - Floating Text Input Component (Isolated)
struct FloatingTextInput: View {
    let textPos: CGPoint
    @Binding var editingText: String
    let imageOrigin: CGPoint
    let displaySize: CGSize
    let imageSize: CGSize
    let fontSize: CGFloat
    let textColor: Color
    let opacity: Double
    @GestureState private var localDragOffset: CGSize = .zero
    @FocusState.Binding var isTextFieldFocused: Bool
    let onDragEnded: (CGFloat, CGFloat) -> Void
    let onSubmit: () -> Void
    
    var body: some View {
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height
        let textPoint = CGPoint(
            x: imageOrigin.x + textPos.x * scaleX,
            y: imageOrigin.y + textPos.y * scaleY
        )
        
        let fontSizeOffset = max(fontSize * scaleY, 20)
        let inputBoxOffset = fontSizeOffset + 30
        
        ZStack {
            if !editingText.isEmpty {
                Text(editingText)
                    .font(.system(size: fontSize * scaleX))
                    .foregroundColor(textColor.opacity(opacity))
                    .position(textPoint)
                    .offset(localDragOffset)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .updating($localDragOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    let deltaX = value.translation.width / scaleX
                                    let deltaY = value.translation.height / scaleY
                                    onDragEnded(deltaX, deltaY)
                                }
                        )
                    
                    TextField("Enter text", text: $editingText)
                        .textFieldStyle(.plain)
                        .font(.system(size: fontSize))
                        .foregroundColor(textColor)
                        .padding(8)
                        .frame(width: 180)
                        .focused($isTextFieldFocused)
                        .onSubmit(onSubmit)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                }
                .padding(4)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(8))
            }
            .position(x: textPoint.x, y: textPoint.y + inputBoxOffset)
            .offset(localDragOffset)
        }
    }
}


