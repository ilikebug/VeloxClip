import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = AppSettings.shared
    @State private var section: SettingsSectionID = .appearance

    enum SettingsSectionID: CaseIterable {
        case appearance, history, privacy, pasteStack, shortcuts, advanced

        var title: String {
            switch self {
            case .appearance: return L10n.string("settings.section.appearance")
            case .history:    return L10n.string("settings.section.history")
            case .privacy:    return L10n.string("settings.section.privacy")
            case .pasteStack: return L10n.string("settings.section.pasteStack")
            case .shortcuts:  return L10n.string("settings.section.shortcuts")
            case .advanced:   return L10n.string("settings.section.advanced")
            }
        }

        var icon: String {
            switch self {
            case .appearance: return "circle.lefthalf.filled"
            case .history:    return "clock"
            case .privacy:    return "hand.raised"
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
        // Settings is where the user changes the values whose writes can fail,
        // and it is a separate window from the overlay that used to host the
        // only alert in the app.
        .errorAlert()
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
                case .privacy:    PrivacySection()
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
                // 2000/5000 are safe now that deferred maintenance reclaims the
                // freed pages — before, a large history meant a file that only grew.
                DSSegmented(
                    selection: $settings.historyLimit,
                    options: [(100, "100"), (500, "500"), (1000, "1000"), (2000, "2000"), (5000, "5000")]
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

// MARK: - Privacy

/// The never-record list. Copies made while one of these apps is frontmost
/// never reach history — the defaults cover the common password managers, and
/// the user can add their own or opt out of a default.
private struct PrivacySection: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var settings = AppSettings.shared

    private var blocked: [String] { BlacklistManager.shared.blockedBundleIDs }

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.string("settings.section.privacy"))

            Text(L10n.string("settings.privacy.explainer"))
                .font(.dsCaption)
                .foregroundColor(c.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(blocked, id: \.self) { bundleID in
                    HStack(spacing: 10) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 12))
                            .foregroundColor(c.text2)
                        Text(displayName(for: bundleID))
                            .font(.dsBody)
                            .foregroundColor(c.text)
                        Text(bundleID)
                            .font(.dsCaption2)
                            .foregroundColor(c.text2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button {
                            remove(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(c.text2)
                        .help(L10n.string("settings.privacy.remove"))
                    }
                    .padding(.vertical, 7)

                    if bundleID != blocked.last {
                        Rectangle().fill(c.divider).frame(height: 1)
                    }
                }

                if blocked.isEmpty {
                    Text(L10n.string("settings.privacy.empty"))
                        .font(.dsCaption)
                        .foregroundColor(c.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(c.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.divider, lineWidth: 1))

            Button {
                addApp()
            } label: {
                Label(L10n.string("settings.privacy.add"), systemImage: "plus")
            }
            .dsButton(.secondary, small: true)
            .padding(.top, 12)
        }
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID.components(separatedBy: ".").last ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n.string("settings.privacy.add")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // An app with no bundle identifier cannot be blocked — matching is by
        // identifier. Say so: silently doing nothing in a privacy feature is
        // exactly the failure this feature exists to prevent.
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.string("settings.privacy.noBundleID.title")
            alert.informativeText = L10n.string("settings.privacy.noBundleID.message")
            alert.runModal()
            return
        }

        let matches: (String) -> Bool = { $0.caseInsensitiveCompare(bundleID) == .orderedSame }

        // Re-adding a default the user previously removed is an un-remove,
        // not a duplicate entry.
        settings.blacklistUserRemoved.removeAll(where: matches)
        if !settings.blacklistUserAdded.contains(where: matches),
           !BlacklistManager.defaultBundleIDs.contains(where: matches) {
            settings.blacklistUserAdded.append(bundleID)
        }
    }

    private func remove(_ bundleID: String) {
        let matches: (String) -> Bool = { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
        // Both directions unconditionally: an id can be BOTH user-added and a
        // built-in default (from an older settings row, or because a later
        // release promoted it into the defaults). Branching on `else if` left
        // such an app blocked forever with a button that appeared to do nothing.
        settings.blacklistUserAdded.removeAll(where: matches)
        if BlacklistManager.defaultBundleIDs.contains(where: matches),
           !settings.blacklistUserRemoved.contains(where: matches) {
            settings.blacklistUserRemoved.append(bundleID)
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
    @Environment(\.colorScheme) private var scheme
    @State private var confirmingClear = false

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.string("settings.section.advanced"))

            HStack(spacing: 12) {
                Button(L10n.string("settings.clearCache")) {
                    CacheManager.shared.clearAllCaches()
                }
                .dsButton(.secondary)

                if confirmingClear {
                    // One click used to wipe everything (favorites included) with no way back
                    Text(L10n.string("settings.clearHistory.confirm"))
                        .font(.dsSubheadline)
                        .foregroundColor(c.text2)
                    Button(L10n.string("settings.clearHistory.confirm.yes")) {
                        confirmingClear = false
                        Task { await ClipboardStore.shared.clearHistory() }
                    }
                    .dsButton(.destructive)
                    Button(L10n.string("hud.cancel")) {
                        confirmingClear = false
                    }
                    .dsButton(.secondary)
                } else {
                    Button(L10n.string("settings.clearHistory")) {
                        confirmingClear = true
                    }
                    .dsButton(.destructive)
                }
            }
        }
    }
}
