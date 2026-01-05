import SwiftUI
import AppKit

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

@MainActor
class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowManager()
    
    private var window: OverlayWindow?
    private var lastActiveApp: NSRunningApplication?
    
    func toggleWindow() {
        if let window = window, window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
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
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        window?.orderOut(nil)
    }
    
    func selectAndPaste(_ item: ClipboardItem) {
        // 1. Record target app BEFORE hiding window (more accurate)
        // Try to get the app that was active before we showed the window
        let targetApp = lastActiveApp ?? NSWorkspace.shared.frontmostApplication
        
        // 2. Copy to clipboard
        copyToClipboard(item)
        
        // 3. Hide window
        window?.orderOut(nil)
        
        guard let app = targetApp else {
            NSApp.hide(nil)
            return
        }
        
        // 4. Return focus to the target app explicitly
        app.activate(options: .activateIgnoringOtherApps)
        
        // 5. Targeted Event Injection (PID-based)
        // This is the "Alfred Way" - sending events directly to the target process
        // Use a longer delay to ensure the app has fully received focus
        // Some apps (especially Electron-based) need more time to process focus events
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Double-check that the app is still the frontmost app
            let currentFrontmost = NSWorkspace.shared.frontmostApplication
            let targetPID = app.processIdentifier
            
            // If another app became frontmost, try to reactivate target app
            if currentFrontmost?.processIdentifier != targetPID {
                app.activate(options: .activateIgnoringOtherApps)
                // Wait a bit more before injecting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.injectPasteEvent(to: app)
                }
            } else {
                self.injectPasteEvent(to: app)
            }
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            vUp.postToPid(pid)
        }
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.type == "image", let data = item.data {
            pasteboard.setData(data, forType: .tiff)
            pasteboard.setData(data, forType: .png)
            return
        }
        
        if item.type == "color", let content = item.content {
            pasteboard.setString(content, forType: .string)
            return
        }
        
        if let content = item.content {
            pasteboard.setString(content, forType: .string)
        } else if let data = item.data {
            if item.type == "rtf" {
                pasteboard.setData(data, forType: .rtf)
            }
        }
    }
}
