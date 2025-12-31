import SwiftUI
import Combine

import ServiceManagement

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }
    
    @Published var globalShortcut: String {
        didSet { UserDefaults.standard.set(globalShortcut, forKey: "globalShortcut") }
    }
    
    @Published var aiResponseLanguage: String {
        didSet { UserDefaults.standard.set(aiResponseLanguage, forKey: "aiResponseLanguage") }
    }
    
    private init() {
        self.historyLimit = UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 100
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.globalShortcut = UserDefaults.standard.string(forKey: "globalShortcut") ?? "cmd+shift+v"
        self.aiResponseLanguage = UserDefaults.standard.string(forKey: "aiResponseLanguage") ?? "Chinese"
        
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
