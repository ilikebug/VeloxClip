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
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            toolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
            
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
                    // Background
                    Color.black
                    
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
                            // Calculate scale factor for coordinate conversion
                            let scaleX = displaySize.width / image.size.width
                            let scaleY = displaySize.height / image.size.height
                            
                            // Draw all saved elements
                            for element in editorState.elements {
                                var transform = CGAffineTransform(translationX: imageOrigin.x, y: imageOrigin.y)
                                transform = transform.scaledBy(x: scaleX, y: scaleY)
                                if let transformedCGPath = element.path.copy(using: &transform) {
                                    let transformedPath = Path(transformedCGPath)
                                    
                                    // Only fill for highlight tool, rectangle and circle should be outline only
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
                            
                            // Draw current preview
                            if let currentPath = editorState.currentPath, editorState.isDrawing {
                                var transform = CGAffineTransform(translationX: imageOrigin.x, y: imageOrigin.y)
                                transform = transform.scaledBy(x: scaleX, y: scaleY)
                                if let transformedCGPath = currentPath.copy(using: &transform) {
                                    let transformedPath = Path(transformedCGPath)
                                    
                                    // Only fill for highlight tool, rectangle and circle should be outline only
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
                                    
                                    if !editorState.isDrawing {
                                        editorState.startDrawing(at: imagePoint)
                                    } else {
                                        editorState.updateDrawing(to: imagePoint)
                                    }
                                }
                                .onEnded { _ in
                                    editorState.finishDrawing()
                                }
                        )
                    }
                }
            }
            
            Divider()
            
            // Bottom action bar
            actionBarView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
        }
        .frame(minWidth: 800, minHeight: 600)
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
                        .foregroundColor(editorState.currentTool == tool ? .white : .gray)
                        .frame(width: 32, height: 32)
                        .background(
                            editorState.currentTool == tool ? Color.blue.opacity(0.3) : Color.clear
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
                                    .stroke(Color.white, lineWidth: editorState.currentColor == color ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
                .frame(height: 24)
            
            // Line width slider
            HStack(spacing: 8) {
                Image(systemName: "lineweight")
                    .foregroundColor(.gray)
                Slider(value: $editorState.lineWidth, in: 1...20)
                    .frame(width: 100)
                Text("\(Int(editorState.lineWidth))")
                    .foregroundColor(.gray)
                    .frame(width: 30)
            }
            
            Spacer()
            
            // Undo/Redo
            Button(action: {
                editorState.undo()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(editorState.canUndo() ? .white : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!editorState.canUndo())
            .help("Undo (Cmd+Z)")
            
            Button(action: {
                editorState.redo()
            }) {
                Image(systemName: "arrow.uturn.forward")
                    .foregroundColor(editorState.canRedo() ? .white : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!editorState.canRedo())
            .help("Redo (Cmd+Shift+Z)")
            
            Button(action: {
                editorState.clear()
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.white)
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
            // Set stroke color
            let strokeColor = NSColor(element.color.opacity(element.opacity)).cgColor
            context.setStrokeColor(strokeColor)
            context.setLineWidth(element.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            context.addPath(element.path)
            
            // Only fill for highlight tool, rectangle and circle should be outline only
            if element.type == .highlight {
                let fillColor = NSColor(element.color.opacity(element.opacity * 0.3)).cgColor
                context.setFillColor(fillColor)
                context.fillPath()
                context.addPath(element.path) // Re-add path for stroke
            }
            
            // Stroke for all tools
            context.strokePath()
        }
        
        context.restoreGState()
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create final image
        let finalImage = NSImage(size: imageSize)
        finalImage.addRepresentation(bitmapRep)
        
        return finalImage
    }
}

