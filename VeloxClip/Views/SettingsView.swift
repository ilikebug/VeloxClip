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

            Section("Paste Stack") {
                Toggle("Show Paste Stack HUD", isOn: $settings.showPasteStackHUD)
                    .help("Floating progress panel while a paste queue is active. When off, progress shows in the menu bar instead.")

                Picker("HUD Position", selection: $settings.pasteStackHUDPosition) {
                    Text("Top Center").tag("topCenter")
                    Text("Top Left").tag("topLeft")
                    Text("Top Right").tag("topRight")
                    Text("Bottom Center").tag("bottomCenter")
                    Text("Bottom Left").tag("bottomLeft")
                    Text("Bottom Right").tag("bottomRight")
                    if settings.pasteStackHUDPosition == "custom" {
                        Text("Custom (dragged)").tag("custom")
                    }
                }
                .disabled(!settings.showPasteStackHUD)
                .help("Picking a corner resets a dragged (custom) position")
            }

            Section("Maintenance") {
                Button("Clear Image & Analysis Caches") {
                    CacheManager.shared.clearAllCaches()
                }
                .help("Clear background caches for OCR, embeddings, and content detection. Doesn't delete your history.")

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
            
            Section {
                HStack {
                    Text("Area Screenshot")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.screenshotShortcut)
                        .frame(width: 200, height: 24)
                }
                Text("Capture area screenshot (default: F1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                HStack {
                    Text("Paste Image")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.pasteImageShortcut)
                        .frame(width: 200, height: 24)
                }
                Text("Show floating image from clipboard (default: F3)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("Screen Text Capture")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.textCaptureShortcut)
                        .frame(width: 200, height: 24)
                }
                Text("Select a screen area — recognized text (or QR payload) goes straight to the clipboard (default: F2)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .formStyle(.grouped)
        .onChange(of: settings.globalShortcut) { _, newValue in
            ShortcutManager.shared.updateShortcut(newValue)
        }
        .onChange(of: settings.screenshotShortcut) { _, newValue in
            ShortcutManager.shared.updateScreenshotShortcut(newValue)
        }
        .onChange(of: settings.pasteImageShortcut) { _, newValue in
            ShortcutManager.shared.updatePasteImageShortcut(newValue)
        }
        .onChange(of: settings.textCaptureShortcut) { _, newValue in
            ShortcutManager.shared.updateTextCaptureShortcut(newValue)
        }
    }
}
