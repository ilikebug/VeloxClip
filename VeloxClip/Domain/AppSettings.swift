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
                try? await dbManager.setSetting(key: "historyLimit", value: String(historyLimit))
            }
            onHistoryLimitChanged?()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "launchAtLogin", value: String(launchAtLogin))
            }
            updateLaunchAtLogin()
        }
    }

    @Published var globalShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    try? await dbManager.setSetting(key: "globalShortcut", value: globalShortcut)
                }
            }
            ShortcutManager.shared.update(globalShortcut, for: .windowToggle)
        }
    }

    @Published var screenshotShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    try? await dbManager.setSetting(key: "screenshotShortcut", value: screenshotShortcut)
                }
            }
            ShortcutManager.shared.update(screenshotShortcut, for: .screenshot)
        }
    }

    @Published var pasteImageShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    try? await dbManager.setSetting(key: "pasteImageShortcut", value: pasteImageShortcut)
                }
            }
            ShortcutManager.shared.update(pasteImageShortcut, for: .pasteImage)
        }
    }

    @Published var textCaptureShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    try? await dbManager.setSetting(key: "textCaptureShortcut", value: textCaptureShortcut)
                }
            }
            ShortcutManager.shared.update(textCaptureShortcut, for: .textCapture)
        }
    }

    @Published var showPasteStackHUD: Bool {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "showPasteStackHUD", value: String(showPasteStackHUD))
            }
        }
    }

    // "topCenter" | "bottomCenter" | "bottomRight" | "bottomLeft" | "topRight" | "topLeft" | "custom"
    @Published var pasteStackHUDPosition: String {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "pasteStackHUDPosition", value: pasteStackHUDPosition)
            }
        }
    }

    // "x,y" of the panel origin, set when the user drags the HUD
    @Published var pasteStackHUDCustomOrigin: String {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "pasteStackHUDCustomOrigin", value: pasteStackHUDCustomOrigin)
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
                try? await dbManager.setSetting(key: "appearance", value: appearance)
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
                try? await dbManager.setSetting(key: "appLanguage", value: appLanguage.rawValue)
            }
        }
    }

    private var isInitializing = true

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

        if autoLoad {
            Task { await load() }
        }
    }

    /// Applies persisted values, then reconciles the login item with the system.
    func load() async {
        await loadSettings()
        isInitializing = false
        settingsLoaded = true
        syncLaunchAtLoginWithSystem()
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
            try? await dbManager.setSetting(key: "historyLimit", value: "100")
        }

        // Load launchAtLogin
        if let launchAtLoginStr = await dbManager.getSetting(key: "launchAtLogin") {
            self.launchAtLogin = launchAtLoginStr == "true"
        } else {
            try? await dbManager.setSetting(key: "launchAtLogin", value: "false")
        }

        // Load globalShortcut
        if let shortcut = await dbManager.getSetting(key: "globalShortcut") {
            self.globalShortcut = shortcut
        } else {
            try? await dbManager.setSetting(key: "globalShortcut", value: "cmd+shift+v")
        }

        // Load screenshotShortcut
        if let shortcut = await dbManager.getSetting(key: "screenshotShortcut") {
            self.screenshotShortcut = shortcut
        } else {
            try? await dbManager.setSetting(key: "screenshotShortcut", value: "f1")
        }

        // Load pasteImageShortcut
        if let shortcut = await dbManager.getSetting(key: "pasteImageShortcut") {
            self.pasteImageShortcut = shortcut
        } else {
            try? await dbManager.setSetting(key: "pasteImageShortcut", value: "f3")
        }

        // Load textCaptureShortcut
        if let shortcut = await dbManager.getSetting(key: "textCaptureShortcut") {
            self.textCaptureShortcut = shortcut
        } else {
            try? await dbManager.setSetting(key: "textCaptureShortcut", value: "f2")
        }

        // Load paste stack HUD settings
        if let show = await dbManager.getSetting(key: "showPasteStackHUD") {
            self.showPasteStackHUD = show == "true"
        } else {
            try? await dbManager.setSetting(key: "showPasteStackHUD", value: "true")
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
            try? await dbManager.setSetting(key: "pasteStackHUDPosition", value: "bottomCenter")
        }
        try? await dbManager.setSetting(key: "hudPositionBottomCenterMigration", value: "done")
        try? await dbManager.deleteSetting(key: "hudPositionTopCenterMigration")

        if let origin = await dbManager.getSetting(key: "pasteStackHUDCustomOrigin") {
            self.pasteStackHUDCustomOrigin = origin
        }

        // Appearance (light by default; not following the system)
        if let appearanceValue = await dbManager.getSetting(key: "appearance") {
            self.appearance = appearanceValue
        } else {
            try? await dbManager.setSetting(key: "appearance", value: "light")
        }
        applyAppearance()

        if let languageValue = await dbManager.getSetting(key: "appLanguage"),
           let language = AppLanguage(rawValue: languageValue) {
            self.appLanguage = language
        } else {
            try? await dbManager.setSetting(key: "appLanguage", value: AppLanguage.system.rawValue)
        }

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
