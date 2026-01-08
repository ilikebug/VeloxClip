import SwiftUI
import UserNotifications

@main
struct VeloxClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = ClipboardMonitor()
    
    @Environment(\.openWindow) var openWindow
    
    var body: some Scene {
        // No WindowGroup for main app, but we need one for Settings
        WindowGroup(id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 350)
        
        MenuBarExtra("Velox Clip", systemImage: "paperclip.circle.fill") {
            Button("Show Clipboard") {
                WindowManager.shared.toggleWindow()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            
            Button("Paste Image") {
                PasteImageService.shared.showPasteImage()
            }
            
            Divider()
            
            Button("Preferences...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
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

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if another instance is already running
        if isAnotherInstanceRunning() {
            print("⚠️ Another instance of VeloxClip is already running. Activating it and quitting this instance.")
            activateExistingInstance()
            NSApplication.shared.terminate(nil)
            return
        }
        
        // Setup notification center delegate FIRST, before requesting permission
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Request notification permission after a short delay to ensure app is fully initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestNotificationPermission()
        }
        
        // Register all global shortcuts
        ShortcutManager.shared.registerAllShortcuts()
        
        // Note: Window will be shown when user presses the shortcut or clicks menu item
        // Removed auto-show on launch to avoid interrupting user workflow
    }
    
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        
        // First check current authorization status
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // Request authorization
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("Failed to request notification permission: \(error.localizedDescription)")
                        } else if granted {
                            print("✅ Notification permission granted")
                        } else {
                            print("⚠️ Notification permission denied")
                        }
                    }
                }
            case .authorized:
                print("✅ Notification permission already granted")
            case .denied:
                print("⚠️ Notification permission denied by user")
            case .provisional:
                print("ℹ️ Notification permission is provisional")
            @unknown default:
                print("⚠️ Unknown notification authorization status")
            }
        }
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        // Use .list for macOS 11+, fallback to .alert for older versions
        if #available(macOS 11.0, *) {
            completionHandler([.list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    // Handle user interaction with notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap if needed
        completionHandler()
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
        // Ensure API Key is saved before app terminates
        Task {
            let apiKey = await MainActor.run { AppSettings.shared.openRouterAPIKey }
            if !apiKey.isEmpty {
                do {
                    try await DatabaseManager.shared.setSetting(key: "openRouterAPIKey", value: apiKey)
                    print("✅ OpenRouter API Key saved on app termination")
                } catch {
                    print("❌ Failed to save OpenRouter API Key on termination: \(error)")
                }
            }
        }
    }
}
