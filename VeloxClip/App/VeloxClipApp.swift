import SwiftUI

@main
struct VeloxClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = ClipboardMonitor()
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

struct MenuBarDashboard: View {
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var stack = PasteStackService.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    let openSettings: () -> Void

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(spacing: 0) {
            header(c)
            stats(c)
            quickActions(c)
            queueControls(c)
            footer(c)
        }
        .frame(width: 330)
        .background(c.window)
        .onAppear {
            store.loadFavorites()
        }
    }

    private var presentation: MenuBarDashboardPresentation {
        MenuBarDashboardPresentation(
            historyCount: store.items.count,
            favoriteCount: store.favoriteItems.count,
            stagedCount: stack.staged.count,
            queueCount: stack.queue.count,
            cursor: stack.cursor,
            phase: stack.phase
        )
    }

    private func header(_ c: DSColors) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(c.accent)
                Image(systemName: "paperclip")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("VeloxClip")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(c.text)
                Text(presentation.statusText(language: settings.appLanguage))
                    .font(.system(size: 11.5))
                    .foregroundColor(c.text2)
            }

            Spacer()

            Button {
                performDashboardAction(.settings) {
                    openSettings()
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(c.text2)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(c.chip))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func stats(_ c: DSColors) -> some View {
        HStack(spacing: 8) {
            statCard(L10n.string("menubar.stat.history", language: settings.appLanguage), presentation.historyValue, icon: "clock.arrow.circlepath", c)
            statCard(L10n.string("menubar.stat.favorites", language: settings.appLanguage), presentation.favoriteValue, icon: "star", c)
            statCard(L10n.string("menubar.stat.queue", language: settings.appLanguage), presentation.queueValue, icon: "square.stack.3d.up", c)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func statCard(_ label: String, _ value: String, icon: String, _ c: DSColors) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(c.text2)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(c.text2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c.card))
    }

    private func quickActions(_ c: DSColors) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            dashboardAction(L10n.string("menubar.action.openClipboard", language: settings.appLanguage), icon: "rectangle.stack", isPrimary: true, c: c) {
                performDashboardAction(.openClipboard) {
                    WindowManager.shared.toggleWindow()
                }
            }
            dashboardAction(L10n.string("menubar.action.pasteImage", language: settings.appLanguage), icon: "photo.on.rectangle", c: c) {
                performDashboardAction(.pasteImage) {
                    PasteImageService.shared.showPasteImage()
                }
            }
            dashboardAction(L10n.string("menubar.action.captureText", language: settings.appLanguage), icon: "text.viewfinder", c: c) {
                performDashboardAction(.captureText) {
                    TextCaptureService.shared.captureText()
                }
            }
            dashboardAction(L10n.string("menubar.action.settings", language: settings.appLanguage), icon: "gearshape", c: c) {
                performDashboardAction(.settings) {
                    openSettings()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func dashboardAction(_ title: String,
                                 icon: String,
                                 isPrimary: Bool = false,
                                 c: DSColors,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isPrimary ? .white : c.text)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPrimary ? c.accent : c.chip)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func queueControls(_ c: DSColors) -> some View {
        if stack.phase == .active || stack.phase == .paused {
            VStack(spacing: 8) {
                Divider().overlay(c.divider)
                HStack(spacing: 8) {
                    if stack.phase == .paused {
                        dashboardAction(L10n.string("menubar.action.resumeQueue", language: settings.appLanguage), icon: "play.fill", isPrimary: true, c: c) {
                            performDashboardAction(.resumeQueue) {
                                stack.resume()
                            }
                        }
                    }
                    dashboardAction(L10n.string("menubar.action.cancelQueue", language: settings.appLanguage), icon: "xmark", c: c) {
                        performDashboardAction(.cancelQueue) {
                            stack.cancel()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        } else if !stack.staged.isEmpty {
            VStack(spacing: 8) {
                Divider().overlay(c.divider)
                HStack(spacing: 8) {
                    dashboardAction(L10n.string("menubar.action.startQueue", language: settings.appLanguage), icon: "play.fill", isPrimary: true, c: c) {
                        Task { @MainActor in
                            await stack.startIfStaged()
                            finishDashboardAction(.startQueue)
                        }
                    }
                    dashboardAction(L10n.string("menubar.action.clearQueue", language: settings.appLanguage), icon: "trash", c: c) {
                        performDashboardAction(.clearQueue) {
                            stack.clearStaged()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func performDashboardAction(_ dashboardAction: MenuBarDashboardAction,
                                        operation: () -> Void) {
        operation()
        finishDashboardAction(dashboardAction)
    }

    private func finishDashboardAction(_ dashboardAction: MenuBarDashboardAction) {
        if dashboardAction.dismissesPanel {
            dismiss()
        }
        if dashboardAction.hidesAppAfterAction {
            NSApp.hide(nil)
        }
    }

    private func footer(_ c: DSColors) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(c.divider)
            HStack {
                if let footerShortcutHint = presentation.footerShortcutHint {
                    Text(footerShortcutHint)
                        .font(.system(size: 10.8))
                        .foregroundColor(c.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Button(L10n.string("menubar.quit", language: settings.appLanguage)) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(c.text2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// Shows paste-stack progress in the menu bar when the HUD is disabled,
// so the queue is never completely invisible
struct MenuBarLabel: View {
    @ObservedObject var stack = PasteStackService.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        if stack.phase != .idle && !settings.showPasteStackHUD {
            Image(systemName: "list.number")
            Text("\(min(stack.cursor + 1, stack.queue.count))/\(stack.queue.count)")
        } else {
            Image(systemName: "paperclip.circle.fill")
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
        
        // Apply the saved appearance (defaults to light) before any window shows
        AppSettings.shared.applyAppearance()

        // Register all global shortcuts
        ShortcutManager.shared.registerAllShortcuts()
        WindowManager.shared.startTrackingTargetApps()

        // Paste stack HUD reacts to PasteStackService phase changes
        Task { @MainActor in
            PasteStackHUDController.shared.activate()
        }
        
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
