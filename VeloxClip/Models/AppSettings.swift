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
    
    @Published var aiResponseLanguage: String {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "aiResponseLanguage", value: aiResponseLanguage)
            }
        }
    }
    
    @Published var openRouterAPIKey: String {
        didSet {
            Task {
                try? await dbManager.setSetting(key: "openRouterAPIKey", value: openRouterAPIKey)
            }
        }
    }
    
    private init() {
        // Initialize with default values first
        self.historyLimit = 100
        self.launchAtLogin = false
        self.globalShortcut = "cmd+shift+v"
        self.aiResponseLanguage = "Chinese"
        self.openRouterAPIKey = ""
        
        // Load settings from database asynchronously
        Task {
            await loadSettings()
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
            }
        } else {
            try? await dbManager.setSetting(key: "openRouterAPIKey", value: "")
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
