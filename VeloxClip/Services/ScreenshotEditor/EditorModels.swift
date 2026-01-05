import Foundation
import SwiftUI
import CoreGraphics

// Editor tool types
enum EditorTool: String, CaseIterable, Identifiable {
    case pen = "Pen"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case circle = "Circle"
    case line = "Line"
    case highlight = "Highlight"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .pen: return "pencil"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .highlight: return "highlighter"
        }
    }
}

// Drawing element types
enum DrawingElementType {
    case pen
    case arrow
    case rectangle
    case circle
    case line
    case highlight
}

// Drawing element model
struct DrawingElement: Identifiable, Equatable {
    let id: UUID
    let type: DrawingElementType
    let path: CGPath
    let color: Color
    let lineWidth: CGFloat
    let opacity: Double
    let startPoint: CGPoint
    let endPoint: CGPoint
    
    init(
        id: UUID = UUID(),
        type: DrawingElementType,
        path: CGPath,
        color: Color,
        lineWidth: CGFloat,
        opacity: Double = 1.0,
        startPoint: CGPoint,
        endPoint: CGPoint
    ) {
        self.id = id
        self.type = type
        self.path = path
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    
    static func == (lhs: DrawingElement, rhs: DrawingElement) -> Bool {
        lhs.id == rhs.id
    }
}

// Preset colors
extension Color {
    static let editorColors: [Color] = [
        .red, .orange, .yellow, .green,
        .blue, .purple, .pink, .black,
        .white, .gray, .brown, .cyan,
        .indigo, .mint, .teal, .secondary
    ]
}

