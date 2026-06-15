import SwiftUI

struct SettingsView: View {
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Self-drawn tab switcher (replaces TabView, whose tab bar chrome
            // differs across macOS versions)
            HStack(spacing: 8) {
                tabButton("General", systemImage: "gear", index: 0)
                tabButton("Shortcuts", systemImage: "keyboard", index: 1)
            }
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.4)

            ScrollView {
                Group {
                    if tab == 0 {
                        GeneralSettingsView()
                    } else {
                        ShortcutsSettingsView()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 500, height: 380)
    }

    private func tabButton(_ title: String, systemImage: String, index: Int) -> some View {
        Button(action: { tab = index }) {
            Label(title, systemImage: systemImage)
        }
        .dsButton(tab == index ? .prominent : .secondary, small: true)
    }
}

// MARK: - Reusable settings building blocks

private struct SettingsSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.dsCaption.bold())
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
}

// Label + self-drawn dropdown (replaces Picker, whose menu/segmented chrome
// changed across macOS releases)
private struct SettingsMenu<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(value: T, label: String)]
    var disabled: Bool = false

    var body: some View {
        HStack {
            Text(title).font(.dsBody)
            Spacer()
            Menu {
                ForEach(options, id: \.value) { option in
                    Button(option.label) { selection = option.value }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentLabel).lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .compactMenuLabel()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
        }
    }

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? ""
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
                SettingsMenu(
                    title: "Appearance",
                    selection: $settings.appearance,
                    options: [("light", "Light"), ("dark", "Dark")]
                )
                .help("Light or Dark — applies app-wide and stays fixed regardless of your macOS appearance")

                SettingsMenu(
                    title: "History Limit",
                    selection: $settings.historyLimit,
                    options: [(50, "50 items"), (100, "100 items"), (500, "500 items"), (1000, "1000 items")]
                )
                .help("Maximum number of items to keep in history")

                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.dsSwitch)
                    .font(.dsBody)
                    .help("Automatically start Velox Clip when you log in")
            }

            SettingsSection(title: "Paste Stack") {
                Toggle("Show Paste Stack HUD", isOn: $settings.showPasteStackHUD)
                    .toggleStyle(.dsSwitch)
                    .font(.dsBody)
                    .help("Floating progress panel while a paste queue is active. When off, progress shows in the menu bar instead.")

                SettingsMenu(
                    title: "HUD Position",
                    selection: $settings.pasteStackHUDPosition,
                    options: hudPositionOptions,
                    disabled: !settings.showPasteStackHUD
                )
                .help("Picking a corner resets a dragged (custom) position")
            }

            SettingsSection(title: "Maintenance") {
                Button("Clear Image & Analysis Caches") {
                    CacheManager.shared.clearAllCaches()
                }
                .dsButton()
                .help("Clear background caches for OCR, embeddings, and content detection. Doesn't delete your history.")

                Button("Clear All History") {
                    ClipboardStore.shared.clearAll()
                }
                .dsButton(.destructive)
            }
        }
    }

    // "Custom (dragged)" is only a valid choice once the user has dragged the HUD
    private var hudPositionOptions: [(value: String, label: String)] {
        var opts: [(value: String, label: String)] = [
            ("topCenter", "Top Center"),
            ("topLeft", "Top Left"),
            ("topRight", "Top Right"),
            ("bottomCenter", "Bottom Center"),
            ("bottomLeft", "Bottom Left"),
            ("bottomRight", "Bottom Right")
        ]
        if settings.pasteStackHUDPosition == "custom" {
            opts.append(("custom", "Custom (dragged)"))
        }
        return opts
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            shortcutSection(
                "Toggle Window",
                shortcut: $settings.globalShortcut,
                hint: "Click the button and press your desired key combination"
            )
            shortcutSection(
                "Area Screenshot",
                shortcut: $settings.screenshotShortcut,
                hint: "Capture area screenshot (default: F1)"
            )
            shortcutSection(
                "Paste Image",
                shortcut: $settings.pasteImageShortcut,
                hint: "Show floating image from clipboard (default: F3)"
            )
            shortcutSection(
                "Screen Text Capture",
                shortcut: $settings.textCaptureShortcut,
                hint: "Select a screen area — recognized text (or QR payload) goes straight to the clipboard (default: F2)"
            )
        }
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

    private func shortcutSection(_ label: String, shortcut: Binding<String>, hint: String) -> some View {
        SettingsSection {
            HStack {
                Text(label).font(.dsBody)
                Spacer()
                ShortcutRecorder(shortcut: shortcut)
                    .frame(width: 200, height: 24)
            }
            Text(hint)
                .font(.dsCaption)
                .foregroundColor(.secondary)
        }
    }
}
