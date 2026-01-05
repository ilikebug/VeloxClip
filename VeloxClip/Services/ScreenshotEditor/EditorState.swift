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
        }
        
        let element = DrawingElement(
            type: elementType,
            path: path,
            color: currentColor,
            lineWidth: lineWidth,
            opacity: currentTool == .highlight ? 0.5 : opacity,
            startPoint: startPoint,
            endPoint: endPoint
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
            // Add arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 15
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
            path.move(to: end)
            path.addLine(to: arrowPoint2)
            
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
        }
        
        return path
    }
}

