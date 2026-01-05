import SwiftUI
import Combine

import ServiceManagement

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let dbManager = DatabaseManager.shared
    
    @Published var historyLimit: Int {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "historyLimit", value: String(historyLimit))
            }
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "launchAtLogin", value: String(launchAtLogin))
            }
            updateLaunchAtLogin()
        }
    }
    
    @Published var globalShortcut: String {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "globalShortcut", value: globalShortcut)
            }
        }
    }
    
    @Published var screenshotShortcut: String {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "screenshotShortcut", value: screenshotShortcut)
            }
        }
    }
    
    @Published var pasteImageShortcut: String {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "pasteImageShortcut", value: pasteImageShortcut)
            }
        }
    }
    
    @Published var aiResponseLanguage: String {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "aiResponseLanguage", value: aiResponseLanguage)
            }
        }
    }
    
    @Published var openRouterAPIKey: String {
        didSet {
            // Only save if not initializing (avoid saving empty string on init)
            guard !isInitializing else { return }
            
            // Save immediately when changed
            Task {
                do {
                    try await dbManager.setSetting(key: "openRouterAPIKey", value: openRouterAPIKey)
                    print("✅ OpenRouter API Key saved successfully (length: \(openRouterAPIKey.count))")
                } catch {
                    print("❌ Failed to save OpenRouter API Key: \(error)")
                    ErrorHandler.shared.handle(error)
                }
            }
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
        self.aiResponseLanguage = "Chinese"
        self.openRouterAPIKey = ""
        
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
        
        // Load aiResponseLanguage
        if let language = await dbManager.getSetting(key: "aiResponseLanguage") {
            await MainActor.run {
                self.aiResponseLanguage = language
            }
        } else {
            try? await dbManager.setSetting(key: "aiResponseLanguage", value: "Chinese")
        }
        
        // Load openRouterAPIKey
        if let apiKey = await dbManager.getSetting(key: "openRouterAPIKey") {
            await MainActor.run {
                self.openRouterAPIKey = apiKey
                print("✅ Loaded OpenRouter API Key from database (length: \(apiKey.count))")
            }
        } else {
            // Only initialize empty string if it doesn't exist in database
            // Don't overwrite if user has already set a value
            let currentValue = await MainActor.run { self.openRouterAPIKey }
            if currentValue.isEmpty {
                // Only initialize if still empty (user hasn't set it yet)
                try? await dbManager.setSetting(key: "openRouterAPIKey", value: "")
                print("ℹ️ OpenRouter API Key not found in database, initialized as empty")
            }
        }
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
