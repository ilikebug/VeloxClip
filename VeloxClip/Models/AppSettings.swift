import SwiftUI
import Combine

import ServiceManagement

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let dbManager = DatabaseManager.shared
    
    @Published var historyLimit: Int {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "historyLimit", value: String(historyLimit))
            }
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
            ShortcutManager.shared.updateShortcut(globalShortcut)
        }
    }
    
    @Published var screenshotShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    try? await dbManager.setSetting(key: "screenshotShortcut", value: screenshotShortcut)
                }
            }
            ShortcutManager.shared.updateScreenshotShortcut(screenshotShortcut)
        }
    }
    
    @Published var pasteImageShortcut: String {
        didSet {
            if !isInitializing {
                Task {
                    try? await dbManager.setSetting(key: "pasteImageShortcut", value: pasteImageShortcut)
                }
            }
            ShortcutManager.shared.updatePasteImageShortcut(pasteImageShortcut)
        }
    }
    
    private var isInitializing = true
    
    private init() {
        // Initialize with default values first
        self.historyLimit = 100
        self.launchAtLogin = false
        self.globalShortcut = "cmd+shift+v"
        self.screenshotShortcut = "f1"
        self.pasteImageShortcut = "f3"


        // Load settings from database asynchronously
        Task {
            await loadSettings()
            // Mark initialization complete after loading
            await MainActor.run {
                self.isInitializing = false
            }
        }
        
        // Sync state with system on launch
        if #available(macOS 13.0, *) {
            let currentStatus = SMAppService.mainApp.status
            if currentStatus == .enabled && !self.launchAtLogin {
                self.launchAtLogin = true
            } else if currentStatus != .enabled && self.launchAtLogin {
                // If system says disabled but we thought enabled, trust system or try to re-enable?
                // Let's trust system for now to avoid loops
                self.launchAtLogin = false
            }
        }
    }
    
    private func loadSettings() async {
        // Load historyLimit
        if let historyLimitStr = await dbManager.getSetting(key: "historyLimit"),
           let limit = Int(historyLimitStr) {
            await MainActor.run {
                self.historyLimit = limit
            }
        } else {
            try? await dbManager.setSetting(key: "historyLimit", value: "100")
        }
        
        // Load launchAtLogin
        if let launchAtLoginStr = await dbManager.getSetting(key: "launchAtLogin") {
            await MainActor.run {
                self.launchAtLogin = launchAtLoginStr == "true"
            }
        } else {
            try? await dbManager.setSetting(key: "launchAtLogin", value: "false")
        }
        
        // Load globalShortcut
        if let shortcut = await dbManager.getSetting(key: "globalShortcut") {
            await MainActor.run {
                self.globalShortcut = shortcut
            }
        } else {
            try? await dbManager.setSetting(key: "globalShortcut", value: "cmd+shift+v")
        }
        
        // Load screenshotShortcut
        if let shortcut = await dbManager.getSetting(key: "screenshotShortcut") {
            await MainActor.run {
                self.screenshotShortcut = shortcut
            }
        } else {
            try? await dbManager.setSetting(key: "screenshotShortcut", value: "f1")
        }
        
        // Load pasteImageShortcut
        if let shortcut = await dbManager.getSetting(key: "pasteImageShortcut") {
            await MainActor.run {
                self.pasteImageShortcut = shortcut
            }
        } else {
            try? await dbManager.setSetting(key: "pasteImageShortcut", value: "f3")
        }
        
        // LLM integration was removed — clean up any previously stored credentials/config
        // so an API key doesn't linger in the settings table
        try? await dbManager.deleteSetting(key: "openRouterAPIKey")
        try? await dbManager.deleteSetting(key: "openRouterModel")
        try? await dbManager.deleteSetting(key: "aiResponseLanguage")
    }
    
    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
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
                // Revert toggle if failed? 
                // For now just log it.
            }
        }
    }
}
