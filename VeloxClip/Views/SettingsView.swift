import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 500, height: 350)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section {
                Picker("History Limit", selection: $settings.historyLimit) {
                    Text("50 items").tag(50)
                    Text("100 items").tag(100)
                    Text("500 items").tag(500)
                    Text("1000 items").tag(1000)
                }
                .help("Maximum number of items to keep in history")
                
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .help("Automatically start Velox Clip when you log in")
            }
            
            Section("AI Settings") {
                Picker("AI Response Language", selection: $settings.aiResponseLanguage) {
                    Text("中文 (Chinese)").tag("Chinese")
                    Text("English").tag("English")
                    Text("日本語 (Japanese)").tag("Japanese")
                    Text("한국어 (Korean)").tag("Korean")
                    Text("Español (Spanish)").tag("Spanish")
                    Text("Français (French)").tag("French")
                    Text("Deutsch (German)").tag("German")
                }
                .help("Language for AI responses (summary, code explanation, etc.)")
            }
            
            Section {
                Button("Clear All History") {
                    ClipboardStore.shared.clearAll()
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .formStyle(.grouped)
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Toggle Window")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.globalShortcut)
                        .frame(width: 200, height: 24)
                }
                Text("Click the button and press your desired key combination")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .formStyle(.grouped)
        .onChange(of: settings.globalShortcut) { newValue in
            ShortcutManager.shared.updateShortcut(newValue)
        }
    }
}
