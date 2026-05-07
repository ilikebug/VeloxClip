import SwiftUI

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
            NSApplication.shared.terminate(nil)
            return
        }
        
        // Register all global shortcuts
        ShortcutManager.shared.registerAllShortcuts()
        
        // Note: Window will be shown when user presses the shortcut or clicks menu item
        // Removed auto-show on launch to avoid interrupting user workflow
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
