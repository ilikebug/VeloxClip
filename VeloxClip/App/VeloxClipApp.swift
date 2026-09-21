import SwiftUI

@main
struct VeloxClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings.shared
    
    @Environment(\.openWindow) var openWindow
    
    var body: some Scene {
        // No WindowGroup for main app, but we need one for Settings
        WindowGroup(id: "settings") {
            SettingsView()
                .environment(\.locale, L10n.locale(for: settings.appLanguage))
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 350)
        
        MenuBarExtra {
            MenuBarDashboard(openSettings: {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            })
            .environment(\.locale, L10n.locale(for: settings.appLanguage))
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here, not by the App struct: SwiftUI builds App-level `@StateObject`s
    /// before/independently of the launch callbacks, so a monitor created there
    /// would start polling before the single-instance claim had run.
    @MainActor private var monitor: ClipboardMonitor?

    private var ownsInstanceLock = false

    // Claim the lock as early as AppKit will let us — before
    // applicationDidFinishLaunching, and before any window or timer exists.
    func applicationWillFinishLaunching(_ notification: Notification) {
        ownsInstanceLock = SingleInstanceGuard.claim()
        if !ownsInstanceLock {
            print("⚠️ Another instance of VeloxClip is already running. Activating it and quitting this instance.")
            activateExistingInstance()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // terminate(nil) is asynchronous, so willFinishLaunching's exit may not
        // have taken effect yet. Do no work in the losing process.
        guard ownsInstanceLock else { return }

        // Apply the saved appearance (defaults to light) before any window shows
        AppSettings.shared.applyAppearance()

        // View caches announce themselves so CacheManager can clear them
        // without Services naming a SwiftUI view type
        ViewCaches.registerAll()

        // Register all global shortcuts
        ShortcutManager.shared.registerAllShortcuts()
        WindowManager.shared.startTrackingTargetApps()

        // Only now may this process read the pasteboard or write the database
        let monitor = ClipboardMonitor()
        self.monitor = monitor
        monitor.start()

        // Paste stack HUD reacts to PasteStackService phase changes
        Task { @MainActor in
            PasteStackHUDController.shared.activate()
        }

        // One-time schema maintenance, deliberately after launch: it scans every
        // blob, so running it inside the DB actor's initializer blocked the first
        // history load behind it.
        Task.detached(priority: .utility) {
            await DatabaseManager.shared.runDeferredMaintenance()
        }
        
        // Note: Window will be shown when user presses the shortcut or clicks menu item
        // Removed auto-show on launch to avoid interrupting user workflow
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
