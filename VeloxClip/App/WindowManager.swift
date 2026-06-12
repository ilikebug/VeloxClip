import SwiftUI
import AppKit
import ApplicationServices

extension Notification.Name {
    // Posted every time the overlay is about to be shown, so MainView can reset its state
    static let veloxOverlayWillShow = Notification.Name("veloxOverlayWillShow")
}

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    // Esc fallback: works even when focus is not in the search field
    override func cancelOperation(_ sender: Any?) {
        WindowManager.shared.hideOverlay()
    }

    // Menu-bar apps may lack an Edit menu, so standard editing key equivalents
    // (copy selected preview text, paste into the search field, …) never resolve
    // through the main menu — route them down the responder chain manually
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            let action: Selector?
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": action = #selector(NSText.copy(_:))
            case "x": action = #selector(NSText.cut(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var window: OverlayWindow?
    private var lastActiveApp: NSRunningApplication?

    override private init() {
        super.init()
        // The resign-key handler keeps the window visible while a popover is key,
        // so we must also hide it when the whole app loses focus
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WindowManager.shared.hideOverlay()
            }
        }
    }

    func toggleWindow() {
        if let window = window, window.isVisible {
            hideOverlay()
        } else {
            showWindow()
        }
    }

    // Central hide path: closing the overlay (by any means) is what arms a
    // staged paste stack
    func hideOverlay() {
        window?.orderOut(nil)
        Task { @MainActor in
            await PasteStackService.shared.startIfStaged()
        }
    }

    private func showWindow() {
        // Record the current frontmost app so we can return focus to it later
        lastActiveApp = NSWorkspace.shared.frontmostApplication

        if window == nil {
            let contentView = MainView()

            let hostingController = NSHostingController(rootView: contentView)

            let win = OverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            win.center()
            win.isReleasedWhenClosed = false
            win.contentView = hostingController.view
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = true
            win.level = .mainMenu // Higher level to appear over full-screen apps
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

            // Allow clicking and dragging the window background
            win.isMovableByWindowBackground = true

            win.delegate = self

            self.window = win
        }

        NotificationCenter.default.post(name: .veloxOverlayWillShow, object: nil)

        // Activate app first to ensure it can receive focus
        NSApp.activate(ignoringOtherApps: true)

        // Center window before showing
        window?.center()

        // Show window and make it key window
        window?.makeKeyAndOrderFront(nil)

        // Ensure window becomes key (for keyboard input). On first launch the
        // window is created in this same runloop turn — activation and the SwiftUI
        // view hierarchy may not be ready yet, so retry instead of a single shot
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let window = self.window, window.isVisible else { return }
                if window.isKeyWindow { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Defer one runloop turn so NSApp.keyWindow reflects the new key window
        Task { @MainActor in
            guard let window = self.window, window.isVisible else { return }

            if let keyWindow = NSApp.keyWindow {
                if keyWindow === window { return }
                // Focus moved into an attached window (popover, menu, sheet) —
                // hiding the overlay here would tear the popover down with it
                var ancestor = keyWindow.parent
                while let current = ancestor {
                    if current === window { return }
                    ancestor = current.parent
                }
            }

            hideOverlay()
        }
    }

    func selectAndPaste(_ item: ClipboardItem) {
        // 1. Record target app BEFORE hiding window (more accurate)
        let targetApp = lastActiveApp ?? NSWorkspace.shared.frontmostApplication

        Task { @MainActor in
            // 2. Copy to clipboard — blobs are lazy-loaded, fetch if needed
            var fullItem = item
            if fullItem.data == nil, fullItem.type == "image" || fullItem.type == "rtf" {
                fullItem.data = await ClipboardStore.shared.loadData(for: item.id)
            }
            fullItem.copyToPasteboard()

            // Move the item to the top of history without rewriting its copy time
            ClipboardStore.shared.markUsed(item.id)

            // 3. Hide window
            self.window?.orderOut(nil)

            guard let app = targetApp else {
                NSApp.hide(nil)
                await PasteStackService.shared.startIfStaged()
                return
            }

            // 4. Return focus to the target app explicitly
            app.activate(options: .activateIgnoringOtherApps)

            // 5. Event injection requires Accessibility permission; without it
            // postToPid silently does nothing — prompt the user instead
            guard Self.ensureAccessibilityPermission() else { return }

            // Targeted Event Injection (PID-based) — the "Alfred Way".
            // Some apps (especially Electron-based) need time to process focus events
            try? await Task.sleep(nanoseconds: 300_000_000)

            let currentFrontmost = NSWorkspace.shared.frontmostApplication
            let targetPID = app.processIdentifier

            // If another app became frontmost, try to reactivate target app
            if currentFrontmost?.processIdentifier != targetPID {
                app.activate(options: .activateIgnoringOtherApps)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            self.injectPasteEvent(to: app)

            // If items are staged, start the stack only after the in-flight
            // injected paste has read the pasteboard
            try? await Task.sleep(nanoseconds: 300_000_000)
            await PasteStackService.shared.startIfStaged()
        }
    }

    // Returns true when the app may inject keyboard events; otherwise shows
    // the system prompt guiding the user to System Settings > Accessibility
    private static func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        // kAXTrustedCheckOptionPrompt is a mutable global the Swift 6 checker rejects;
        // its value is the literal below
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }

    private func injectPasteEvent(to app: NSRunningApplication) {
        let pid = app.processIdentifier
        let source = CGEventSource(stateID: .hidSystemState) // HID state is more reliable

        // Define the keys
        let vKey: UInt16 = 0x09

        // Cmd + V Down
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) else {
            print("Failed to create Cmd+V down event")
            return
        }
        vDown.flags = .maskCommand

        // Cmd + V Up
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            print("Failed to create Cmd+V up event")
            return
        }
        vUp.flags = .maskCommand

        // Post DIRECTLY to the target application's PID
        vDown.postToPid(pid)
        // Small delay between down and up events for better compatibility
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)
            vUp.postToPid(pid)
        }
    }
}
