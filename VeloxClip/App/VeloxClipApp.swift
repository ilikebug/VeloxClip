import SwiftUI

extension Notification.Name {
    static let veloxClipOpenSettings = Notification.Name("com.antigravity.veloxclip.openSettings")
}

@main
struct VeloxClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = ClipboardMonitor()
    @StateObject private var settings = AppSettings.shared
    
    var body: some Scene {
        // Standard Preferences scene — opens via the system "showSettingsWindow:" selector
        // from anywhere (menu, AppDelegate, distributed-notification handler).
        Settings {
            SettingsView()
        }

        // On cold start, AppSettings loads asynchronously from SQLite; the icon may briefly
        // appear with the default `true` before the persisted value is applied (~200ms).
        MenuBarExtra(
            "Velox Clip",
            systemImage: "paperclip.circle.fill",
            isInserted: $settings.showMenuBarIcon
        ) {
            Button("Show Clipboard") {
                WindowManager.shared.toggleWindow()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            
            Button("Paste Image") {
                PasteImageService.shared.showPasteImage()
            }
            
            Divider()
            
            Button("Preferences...") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("Quit Velox Clip") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if another instance is already running
        if isAnotherInstanceRunning() {
            print("⚠️ Another instance of VeloxClip is already running. Activating it and quitting this instance.")
            activateExistingInstance()
            DistributedNotificationCenter.default().postNotificationName(
                .veloxClipOpenSettings,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApplication.shared.terminate(nil)
            return
        }
        
        // Register all global shortcuts
        ShortcutManager.shared.registerAllShortcuts()

        // Listen for "open settings" requests from a duplicate launch attempt.
        DistributedNotificationCenter.default().addObserver(
            forName: .veloxClipOpenSettings,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }

        // Cold-start fallback: if the menu bar icon is hidden, the user has no visible
        // entry point. Wait for AppSettings to finish its initial DB load (up to 5s),
        // then open Settings so they can re-enable it or quit.
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(5)
            while !AppSettings.shared.isLoaded && Date() < deadline {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms poll
                } catch {
                    return // task cancelled (app terminating); abort
                }
            }
            if !AppSettings.shared.showMenuBarIcon {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }

        // Note: Main window will be shown when user presses the shortcut or clicks the menu item.
    }
    
    private func isAnotherInstanceRunning() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.antigravity.veloxclip"
        let runningApps = NSWorkspace.shared.runningApplications
        
        var instanceCount = 0
        for app in runningApps {
            if app.bundleIdentifier == bundleIdentifier {
                // Don't count the current instance
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    instanceCount += 1
                }
            }
        }
        
        return instanceCount > 0
    }
    
    private func activateExistingInstance() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.antigravity.veloxclip"
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if app.bundleIdentifier == bundleIdentifier &&
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                // Activate the existing instance
                app.activate(options: [.activateIgnoringOtherApps])
                break
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // App settings are saved immediately when changed, so no need for extra save here
    }
}
