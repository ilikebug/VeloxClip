import SwiftUI
import AppKit

/// Installs an app-level local key monitor and routes keyDown events to `onKeyDown`,
/// independent of SwiftUI focus/first-responder. Return true from the handler to
/// consume the event (it won't propagate); false to let it through (e.g. typing).
struct KeyMonitor: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.install()
        return NSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Refresh the closure every render so it captures current view state.
        context.coordinator.onKeyDown = onKeyDown
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var monitor: Any?
        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.onKeyDown?(event) == true { return nil } // consumed
                return event
            }
        }
        func remove() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }
    }
}
