import SwiftUI
import AppKit
import Combine

import ServiceManagement

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let dbManager: DatabaseManager

    /// Fired after `historyLimit` changes post-load. `ClipboardStore` hooks this so
    /// shrinking the limit trims immediately, without settings knowing the store.
    var onHistoryLimitChanged: (() -> Void)?

    @Published var historyLimit: Int {
        didSet {
            guard !isInitializing else { return }
            Task {
                await persistSetting(key: "historyLimit", value: String(historyLimit))
            }
            onHistoryLimitChanged?()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isInitializing else { return }
            Task {
                await persistSetting(key: "launchAtLogin", value: String(launchAtLogin))
            }
            updateLaunchAtLogin()
        }
    }

    @Published var globalShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    await persistSetting(key: "globalShortcut", value: globalShortcut)
                }
            }
            ShortcutManager.shared.update(globalShortcut, for: .windowToggle)
        }
    }

    @Published var screenshotShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    await persistSetting(key: "screenshotShortcut", value: screenshotShortcut)
                }
            }
            ShortcutManager.shared.update(screenshotShortcut, for: .screenshot)
        }
    }

    @Published var pasteImageShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    await persistSetting(key: "pasteImageShortcut", value: pasteImageShortcut)
                }
            }
            ShortcutManager.shared.update(pasteImageShortcut, for: .pasteImage)
        }
    }

    @Published var textCaptureShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    await persistSetting(key: "textCaptureShortcut", value: textCaptureShortcut)
                }
            }
            ShortcutManager.shared.update(textCaptureShortcut, for: .textCapture)
        }
    }

    @Published var showPasteStackHUD: Bool {
        didSet {
            guard !isInitializing else { return }
            Task {
                await persistSetting(key: "showPasteStackHUD", value: String(showPasteStackHUD))
            }
        }
    }

    // "topCenter" | "bottomCenter" | "bottomRight" | "bottomLeft" | "topRight" | "topLeft" | "custom"
    @Published var pasteStackHUDPosition: String {
        didSet {
            guard !isInitializing else { return }
            Task {
                await persistSetting(key: "pasteStackHUDPosition", value: pasteStackHUDPosition)
            }
        }
    }

    // "x,y" of the panel origin, set when the user drags the HUD
    @Published var pasteStackHUDCustomOrigin: String {
        didSet {
            guard !isInitializing else { return }
            Task {
                await persistSetting(key: "pasteStackHUDCustomOrigin", value: pasteStackHUDCustomOrigin)
            }
        }
    }

    // "light" | "dark" | "system" — applied app-wide via NSApp.appearance.
    // Defaults to light (fixed, does NOT follow the system) so the UI looks identical
    // on every machine; "dark" pins dark; "system" clears the override and follows macOS.
    @Published var appearance: String {
        didSet {
            guard !isInitializing else { return }
            Task {
                await persistSetting(key: "appearance", value: appearance)
            }
            applyAppearance()
        }
    }

    @Published var appLanguage: AppLanguage {
        willSet {
            L10n.updateCurrentLanguage(newValue)
        }
        didSet {
            guard !isInitializing else { return }
            Task {
                await persistSetting(key: "appLanguage", value: appLanguage.rawValue)
            }
        }
    }

    /// Bundle IDs the user added to the never-record list. Stored as JSON.
    @Published var blacklistUserAdded: [String] {
        didSet {
            BlacklistManager.shared.apply(userAdded: blacklistUserAdded, userRemoved: blacklistUserRemoved)
            guard !isInitializing else { return }
            Task { [blacklistUserAdded] in
                await persistSetting(key: "blacklistUserAdded", value: Self.encodeList(blacklistUserAdded))
            }
        }
    }

    /// Built-in defaults the user opted out of.
    @Published var blacklistUserRemoved: [String] {
        didSet {
            BlacklistManager.shared.apply(userAdded: blacklistUserAdded, userRemoved: blacklistUserRemoved)
            guard !isInitializing else { return }
            Task { [blacklistUserRemoved] in
                await persistSetting(key: "blacklistUserRemoved", value: Self.encodeList(blacklistUserRemoved))
            }
        }
    }

    static func encodeList(_ list: [String]) -> String {
        (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "[]"
    }

    static func decodeList(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private var isInitializing = true

    /// Whether this instance will load itself. Tests construct with
    /// `autoLoad: false` and may never call `load()`, so `waitUntilLoaded()`
    /// must not suspend forever in that case.
    private let autoLoadRequested: Bool

    // True once load() has applied the persisted values. History trimming must
    // not run before this — historyLimit still holds its default and trimming
    // against it could mass-delete history at launch.
    private(set) var settingsLoaded = false

    private convenience init() {
        self.init(dbManager: .shared)
    }

    /// `autoLoad: false` lets tests drive `load()` themselves against an injected DB.
    init(dbManager: DatabaseManager, autoLoad: Bool = true) {
        self.dbManager = dbManager
        self.autoLoadRequested = autoLoad

        // Initialize with default values first
        self.historyLimit = 100
        self.launchAtLogin = false
        self.globalShortcut = "cmd+shift+v"
        self.screenshotShortcut = "f1"
        self.pasteImageShortcut = "f3"
        self.textCaptureShortcut = "f2"
        self.showPasteStackHUD = true
        self.pasteStackHUDPosition = "bottomCenter"
        self.pasteStackHUDCustomOrigin = ""
        self.appearance = "light"
        self.appLanguage = .system
        self.blacklistUserAdded = []
        self.blacklistUserRemoved = []

        if autoLoad {
            Task { await load() }
        }
    }

    /// Applies persisted values, then reconciles the login item with the system.
    /// Persists one setting, reporting failures instead of swallowing them.
    ///
    /// Every write here used to be `try?`: the @Published value updated, the UI
    /// showed the new setting, the write failed, and the next launch read the
    /// old value back. The user saw the app "forget" rather than fail.
    private func persistSetting(key: String, value: String) async {
        do {
            try await dbManager.setSetting(key: key, value: value)
        } catch {
            ErrorHandler.shared.handle(error)
        }
    }

    func load() async {
        await loadSettings()
        isInitializing = false
        settingsLoaded = true
        syncLaunchAtLoginWithSystem()
        for continuation in loadWaiters {
            continuation.resume()
        }
        loadWaiters.removeAll()
    }

    private var loadWaiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until `load()` has applied the stored values.
    ///
    /// Anything that reads a setting to make a decision — rather than to
    /// display it — must await this, or it sees the hardcoded defaults. When
    /// `autoLoad` is false (tests) and nobody calls `load()`, this returns
    /// immediately so a caller cannot hang.
    func waitUntilLoaded() async {
        guard !settingsLoaded else { return }
        guard autoLoadRequested else { return }
        await withCheckedContinuation { continuation in
            loadWaiters.append(continuation)
        }
    }

    // The system is the source of truth for the login item. Runs after load so
    // the correction persists — before, it was applied during init (not persisted)
    // and then overwritten by the stored value, leaving the toggle wrong.
    // Only the two definitive states correct the toggle: `.requiresApproval`
    // (pending in System Settings) and `.notFound` (dev build, test runner)
    // must not flip a user's "on" to "off" or unregister a pending item.
    private func syncLaunchAtLoginWithSystem() {
        switch SMAppService.mainApp.status {
        case .enabled where !launchAtLogin:      launchAtLogin = true
        case .notRegistered where launchAtLogin: launchAtLogin = false
        default: break
        }
    }

    private func loadSettings() async {
        // Load historyLimit — only a positive value is valid; 0/negative would
        // trim history to nothing, so a bad stored value is replaced by the default
        if let historyLimitStr = await dbManager.getSetting(key: "historyLimit"),
           let limit = Int(historyLimitStr), limit > 0 {
            self.historyLimit = limit
        } else {
            await persistSetting(key: "historyLimit", value: "100")
        }

        // Load launchAtLogin
        if let launchAtLoginStr = await dbManager.getSetting(key: "launchAtLogin") {
            self.launchAtLogin = launchAtLoginStr == "true"
        } else {
            await persistSetting(key: "launchAtLogin", value: "false")
        }

        // Load globalShortcut
        if let shortcut = await dbManager.getSetting(key: "globalShortcut") {
            self.globalShortcut = shortcut
        } else {
            await persistSetting(key: "globalShortcut", value: "cmd+shift+v")
        }

        // Load screenshotShortcut
        if let shortcut = await dbManager.getSetting(key: "screenshotShortcut") {
            self.screenshotShortcut = shortcut
        } else {
            await persistSetting(key: "screenshotShortcut", value: "f1")
        }

        // Load pasteImageShortcut
        if let shortcut = await dbManager.getSetting(key: "pasteImageShortcut") {
            self.pasteImageShortcut = shortcut
        } else {
            await persistSetting(key: "pasteImageShortcut", value: "f3")
        }

        // Load textCaptureShortcut
        if let shortcut = await dbManager.getSetting(key: "textCaptureShortcut") {
            self.textCaptureShortcut = shortcut
        } else {
            await persistSetting(key: "textCaptureShortcut", value: "f2")
        }

        // Load paste stack HUD settings
        if let show = await dbManager.getSetting(key: "showPasteStackHUD") {
            self.showPasteStackHUD = show == "true"
        } else {
            await persistSetting(key: "showPasteStackHUD", value: "true")
        }

        // One-time default change: bottomRight then topCenter were earlier
        // launch defaults; a stored value from before this marker existed was
        // auto-written, not a user choice — upgrade it to bottomCenter once
        let positionMigrated = await dbManager.getSetting(key: "hudPositionBottomCenterMigration") != nil
        let oldDefaults = ["bottomRight", "topCenter"]
        if let position = await dbManager.getSetting(key: "pasteStackHUDPosition"),
           positionMigrated || !oldDefaults.contains(position) {
            self.pasteStackHUDPosition = position
        } else {
            await persistSetting(key: "pasteStackHUDPosition", value: "bottomCenter")
        }
        await persistSetting(key: "hudPositionBottomCenterMigration", value: "done")
        try? await dbManager.deleteSetting(key: "hudPositionTopCenterMigration")

        if let origin = await dbManager.getSetting(key: "pasteStackHUDCustomOrigin") {
            self.pasteStackHUDCustomOrigin = origin
        }

        // Appearance (light by default; not following the system)
        if let appearanceValue = await dbManager.getSetting(key: "appearance") {
            self.appearance = appearanceValue
        } else {
            await persistSetting(key: "appearance", value: "light")
        }
        applyAppearance()

        if let languageValue = await dbManager.getSetting(key: "appLanguage"),
           let language = AppLanguage(rawValue: languageValue) {
            self.appLanguage = language
        } else {
            await persistSetting(key: "appLanguage", value: AppLanguage.system.rawValue)
        }

        // Never-record list. Applied to BlacklistManager via the didSet hooks,
        // which run even while isInitializing (only the DB write is guarded).
        self.blacklistUserAdded = Self.decodeList(await dbManager.getSetting(key: "blacklistUserAdded"))
        self.blacklistUserRemoved = Self.decodeList(await dbManager.getSetting(key: "blacklistUserRemoved"))

        // LLM integration was removed — clean up any previously stored credentials/config
        // so an API key doesn't linger in the settings table
        try? await dbManager.deleteSetting(key: "openRouterAPIKey")
        try? await dbManager.deleteSetting(key: "openRouterModel")
        try? await dbManager.deleteSetting(key: "aiResponseLanguage")
    }

    // Force the whole app to the chosen appearance (overrides the system setting),
    // which propagates to every NSWindow/NSPanel and to SwiftUI's colorScheme.
    func applyAppearance() {
        switch appearance {
        case "dark":  NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        default:      NSApplication.shared.appearance = nil // "system" — follow macOS
        }
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
