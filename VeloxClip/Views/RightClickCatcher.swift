import SwiftUI
import AppKit

/// Transparent overlay that reports right-clicks and is invisible to every other
/// mouse event, so the tap/double-tap/hover gestures underneath keep working.
struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }
    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?

        // Only claim the hit for context-click events (right button, or the
        // standard Control-click); everything else falls through to the SwiftUI
        // content below as if this view weren't here.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                // Control-click: AppKit does not synthesize a rightMouseDown for it
                return event.modifierFlags.contains(.control) ? super.hitTest(point) : nil
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func mouseDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.control) else {
                super.mouseDown(with: event)
                return
            }
            onRightClick?()
        }
    }
}
