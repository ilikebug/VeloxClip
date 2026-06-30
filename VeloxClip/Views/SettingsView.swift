import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = AppSettings.shared
    @State private var section: SettingsSectionID = .appearance

    enum SettingsSectionID: CaseIterable {
        case appearance, history, pasteStack, shortcuts, advanced

        var title: String {
            switch self {
            case .appearance: return L10n.string("settings.section.appearance")
            case .history:    return L10n.string("settings.section.history")
            case .pasteStack: return L10n.string("settings.section.pasteStack")
            case .shortcuts:  return L10n.string("settings.section.shortcuts")
            case .advanced:   return L10n.string("settings.section.advanced")
            }
        }

        var icon: String {
            switch self {
            case .appearance: return "circle.lefthalf.filled"
            case .history:    return "clock"
            case .pasteStack: return "square.stack"
            case .shortcuts:  return "keyboard"
            case .advanced:   return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        let c = DSColors(scheme: scheme)
        HStack(spacing: 0) {
            sidebar(c)
            content(c)
        }
        .frame(width: 720, height: 460)
        .background(c.window)
        .environment(\.locale, L10n.locale(for: settings.appLanguage))
    }

    // MARK: Sidebar

    private func sidebar(_ c: DSColors) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSectionID.allCases, id: \.self) { id in
                sidebarRow(id, c)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 184, alignment: .topLeading)
        .frame(maxHeight: .infinity)
        .background(c.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(c.divider).frame(width: 1)
        }
    }

    private func sidebarRow(_ id: SettingsSectionID, _ c: DSColors) -> some View {
        let selected = section == id
        return Button { section = id } label: {
            HStack(spacing: 9) {
                Image(systemName: id.icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(id.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundColor(selected ? c.accent : c.text2)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? c.accentSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ c: DSColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch section {
                case .appearance: AppearanceSection()
                case .history:    HistorySection()
                case .pasteStack: PasteStackSection()
                case .shortcuts:  ShortcutsSection()
                case .advanced:   AdvancedSection()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var subtitle: String? = nil

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(c.text)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundColor(c.text2)
            }
        }
        .padding(.bottom, 18)
    }
}

// MARK: - Setting row (label left, control right)

private struct SettingRow<Control: View>: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    var bottom: CGFloat = 14
    @ViewBuilder var control: Control

    var body: some View {
        let c = DSColors(scheme: scheme)
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundColor(c.text)
            Spacer(minLength: 12)
            control
        }
        .padding(.bottom, bottom)
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.string("settings.section.appearance"))

            SettingRow(label: L10n.string("settings.language")) {
                DSSegmented(
                    selection: $settings.appLanguage,
                    options: AppLanguage.allCases.map { language in
                        (language, language.displayName(language: settings.appLanguage))
                    }
                )
            }

            SettingRow(label: L10n.string("settings.theme")) {
                DSSegmented(
                    selection: $settings.appearance,
                    options: [
                        ("light", L10n.string("settings.theme.light")),
                        ("dark", L10n.string("settings.theme.dark")),
                        ("system", L10n.string("settings.theme.system"))
                    ]
                )
            }

            SettingRow(label: L10n.string("settings.accentColor"), bottom: 0) {
                HStack(spacing: 8) {
                    Circle().fill(c.accent).frame(width: 13, height: 13)
                    Text(L10n.string("settings.theme.system"))
                        .font(.system(size: 12.5))
                        .foregroundColor(c.text2)
                }
            }
        }
    }
}

// MARK: - History

private struct HistorySection: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.string("settings.section.history"))

            SettingRow(label: L10n.string("settings.historyLimit")) {
                DSSegmented(
                    selection: $settings.historyLimit,
                    options: [(50, "50"), (100, "100"), (500, "500"), (1000, "1000")]
                )
            }

            SettingRow(label: L10n.string("settings.launchAtLogin"), bottom: 0) {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.dsSwitch)
                    .labelsHidden()
                    .fixedSize()
            }
        }
    }
}

// MARK: - Paste Stack

private struct PasteStackSection: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var settings = AppSettings.shared

    // 2 rows × 3 cols of corner positions; "custom" only surfaces if already custom
    private var cells: [(value: String, label: String)] {
        [
            ("topLeft", L10n.string("settings.position.topLeft")),
            ("topCenter", L10n.string("settings.position.topCenter")),
            ("topRight", L10n.string("settings.position.topRight")),
            ("bottomLeft", L10n.string("settings.position.bottomLeft")),
            ("bottomCenter", L10n.string("settings.position.bottomCenter")),
            ("bottomRight", L10n.string("settings.position.bottomRight"))
        ]
    }

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.string("settings.section.pasteStack"))

            SettingRow(label: L10n.string("settings.showPasteStackHUD")) {
                Toggle("", isOn: $settings.showPasteStackHUD)
                    .toggleStyle(.dsSwitch)
                    .labelsHidden()
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.hudPosition"))
                    .font(.system(size: 13.5))
                    .foregroundColor(c.text)
                positionGrid(c)
                if settings.pasteStackHUDPosition == "custom" {
                    Text(L10n.string("settings.hudCustomPosition"))
                        .font(.system(size: 11.5))
                        .foregroundColor(c.text2)
                }
            }
            .opacity(settings.showPasteStackHUD ? 1 : 0.45)
            .disabled(!settings.showPasteStackHUD)
        }
    }

    private func positionGrid(_ c: DSColors) -> some View {
        let columns = Array(repeating: GridItem(.fixed(72), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(cells, id: \.value) { cell in
                let selected = settings.pasteStackHUDPosition == cell.value
                Text(cell.label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? .white : c.text2)
                    .frame(width: 72, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? c.accent : c.chip)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { settings.pasteStackHUDPosition = cell.value }
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSection: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.string("settings.section.shortcuts"))

            shortcutRow(L10n.string("settings.shortcut.overlay"), shortcut: $settings.globalShortcut)
            shortcutRow(L10n.string("settings.shortcut.screenshot"), shortcut: $settings.screenshotShortcut)
            shortcutRow(L10n.string("settings.shortcut.textCapture"), shortcut: $settings.textCaptureShortcut)
            shortcutRow(L10n.string("settings.shortcut.pasteImage"), shortcut: $settings.pasteImageShortcut, bottom: 0)
        }
        // Re-registration is driven by AppSettings' didSet on each shortcut
        // property, so binding changes here already update ShortcutManager —
        // no per-field .onChange needed (those were a redundant double-call).
    }

    private func shortcutRow(_ label: String, shortcut: Binding<String>, bottom: CGFloat = 14) -> some View {
        SettingRow(label: label, bottom: bottom) {
            ShortcutRecorder(shortcut: shortcut)
                .frame(width: 200, height: 24)
        }
    }
}

// MARK: - Advanced

private struct AdvancedSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.string("settings.section.advanced"))

            HStack(spacing: 12) {
                Button(L10n.string("settings.clearCache")) {
                    CacheManager.shared.clearAllCaches()
                }
                .dsButton(.secondary)

                Button(L10n.string("settings.clearHistory")) {
                    ClipboardStore.shared.clearAll()
                }
                .dsButton(.destructive)
            }
        }
    }
}
