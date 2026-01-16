import Foundation
import SwiftUI

class EditorState: ObservableObject {
    @Published var currentTool: EditorTool = .pen
    @Published var currentColor: Color = .red
    @Published var lineWidth: CGFloat = 3.0
    @Published var opacity: Double = 1.0
    
    // Drawing elements
    @Published var elements: [DrawingElement] = []
    
    // Undo/Redo stacks
    private var undoStack: [[DrawingElement]] = []
    private var redoStack: [[DrawingElement]] = []
    
    // Current drawing state
    @Published var isDrawing = false
    @Published var currentPath: CGPath?
    @Published var startPoint: CGPoint = .zero
    @Published var endPoint: CGPoint = .zero
    
    // For pen tool - track all points
    @Published var penPoints: [CGPoint] = []
    
    // For text tool
    @Published var textInput: String = ""
    @Published var textPosition: CGPoint?
    @Published var fontSize: CGFloat = 16.0  // Default font size
    
    // Save state snapshot for undo
    func saveState() {
        undoStack.append(elements)
        // Limit undo stack size
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        // Clear redo stack when new action is performed
        redoStack.removeAll()
    }
    
    func undo() {
        guard !undoStack.isEmpty else { return }
        let currentState = elements
        redoStack.append(currentState)
        elements = undoStack.removeLast()
    }
    
    func redo() {
        guard !redoStack.isEmpty else { return }
        let currentState = elements
        undoStack.append(currentState)
        elements = redoStack.removeLast()
    }
    
    func canUndo() -> Bool {
        return !undoStack.isEmpty
    }
    
    func canRedo() -> Bool {
        return !redoStack.isEmpty
    }
    
    func clear() {
        saveState()
        elements.removeAll()
    }
    
    func addElement(_ element: DrawingElement) {
        saveState()
        elements.append(element)
    }
    
    func startDrawing(at point: CGPoint) {
        isDrawing = true
        startPoint = point
        endPoint = point
        
        // For pen tool, initialize points array
        if currentTool == .pen {
            penPoints = [point]
        }
    }
    
    func updateDrawing(to point: CGPoint) {
        guard isDrawing else { return }
        endPoint = point
        
        // For pen tool, add point to array
        if currentTool == .pen {
            penPoints.append(point)
            // Create path from all points
            let path = createPenPath(from: penPoints)
            currentPath = path
        } else {
            // Create temporary path for preview
            let path = createPath(from: startPoint, to: endPoint)
            currentPath = path
        }
    }
    
    func finishDrawing() {
        guard isDrawing else { return }
        isDrawing = false
        
        // Handle text tool separately
        if currentTool == .text {
            guard !textInput.isEmpty, let textPos = textPosition else {
                textInput = ""
                textPosition = nil
                return
            }
            
            // Create a path for text (just a point)
            let path = CGMutablePath()
            path.move(to: textPos)
            
            let element = DrawingElement(
                type: .text,
                path: path,
                color: currentColor,
                lineWidth: lineWidth,
                opacity: opacity,
                startPoint: textPos,
                endPoint: textPos,
                text: textInput,
                fontSize: fontSize,
                rect: nil
            )
            
            addElement(element)
            textInput = ""
            textPosition = nil
            return
        }
        
        guard let path = currentPath else {
            penPoints.removeAll()
            return
        }
        
        let elementType: DrawingElementType
        switch currentTool {
        case .pen: elementType = .pen
        case .arrow: elementType = .arrow
        case .rectangle: elementType = .rectangle
        case .circle: elementType = .circle
        case .line: elementType = .line
        case .highlight: elementType = .highlight
        case .mosaic: elementType = .mosaic
        case .eraser: elementType = .eraser
        case .text: return // Already handled above
        }
        
        var rect: CGRect? = nil
        if currentTool == .mosaic {
            rect = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
        }
        
        let element = DrawingElement(
            type: elementType,
            path: path,
            color: currentColor,
            lineWidth: lineWidth,
            opacity: currentTool == .highlight ? 0.5 : opacity,
            startPoint: startPoint,
            endPoint: endPoint,
            text: nil,
            fontSize: nil,
            rect: rect
        )
        
        addElement(element)
        currentPath = nil
        penPoints.removeAll()
    }
    
    private func createPenPath(from points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard !points.isEmpty else { return path }
        
        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        
        return path
    }
    
    private func createPath(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        
        switch currentTool {
        case .pen:
            // Should not reach here for pen tool
            path.move(to: start)
            path.addLine(to: end)
            
        case .arrow:
            // Draw arrow line
            path.move(to: start)
            path.addLine(to: end)
            
            // Add arrowhead (solid triangle)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
            
            // Scaled arrow head based on line width but capped
            let arrowLength: CGFloat = min(max(lineWidth * 4, 15), length * 0.5)
            let arrowAngle: CGFloat = .pi / 6
            
            let arrowPoint1 = CGPoint(
                x: end.x - arrowLength * cos(angle - arrowAngle),
                y: end.y - arrowLength * sin(angle - arrowAngle)
            )
            let arrowPoint2 = CGPoint(
                x: end.x - arrowLength * cos(angle + arrowAngle),
                y: end.y - arrowLength * sin(angle + arrowAngle)
            )
            
            path.move(to: end)
            path.addLine(to: arrowPoint1)
            path.addLine(to: arrowPoint2)
            path.closeSubpath()
            
        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            path.addRect(rect)
            
        case .circle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            path.addEllipse(in: rect)
            
        case .line:
            path.move(to: start)
            path.addLine(to: end)
            
        case .highlight:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            path.addRect(rect)
            
        case .mosaic:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            path.addRect(rect)
            
        case .eraser:
            // Eraser uses pen-like path
            path.move(to: start)
            path.addLine(to: end)
            
        case .text:
            // This is handled separately
            break
        }
        
        return path
    }
    
    // Remove elements that intersect with eraser path
    func eraseElements(at point: CGPoint, radius: CGFloat) {
        let eraseRadius = max(radius, 10) // Minimum interactive area
        
        let shouldRemove = elements.contains { element in
            // Check bounding box first for optimization
            let boundingBox = element.path.boundingBox
            let expandedBox = boundingBox.insetBy(dx: -eraseRadius, dy: -eraseRadius)
            if !expandedBox.contains(point) {
                return false
            }
            
            // For mosaic/rect/circle, check if point is inside
            if element.type == .mosaic || element.type == .rectangle || element.type == .circle {
                if let rect = element.rect {
                    return rect.insetBy(dx: -eraseRadius, dy: -eraseRadius).contains(point)
                }
                return element.path.contains(point)
            }
            
            // For line-based elements, check distance to path
            // We create a stroked path and check if it contains the point
            let strokedPath = element.path.copy(strokingWithWidth: max(element.lineWidth, eraseRadius * 2), lineCap: .round, lineJoin: .round, miterLimit: 10)
            return strokedPath.contains(point)
        }
        
        if shouldRemove {
            saveState()
            elements.removeAll { element in
                let boundingBox = element.path.boundingBox
                let expandedBox = boundingBox.insetBy(dx: -eraseRadius, dy: -eraseRadius)
                if !expandedBox.contains(point) { return false }
                
                if element.type == .mosaic || element.type == .rectangle || element.type == .circle {
                    if let rect = element.rect {
                        return rect.insetBy(dx: -eraseRadius, dy: -eraseRadius).contains(point)
                    }
                }
                
                let strokedPath = element.path.copy(strokingWithWidth: max(element.lineWidth, eraseRadius * 2), lineCap: .round, lineJoin: .round, miterLimit: 10)
                return strokedPath.contains(point)
            }
        }
    }
}

