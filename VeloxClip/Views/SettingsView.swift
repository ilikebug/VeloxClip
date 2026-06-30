import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var section: SettingsSectionID = .appearance

    enum SettingsSectionID: CaseIterable {
        case appearance, history, pasteStack, shortcuts, advanced

        var title: String {
            switch self {
            case .appearance: return "外观"
            case .history:    return "历史"
            case .pasteStack: return "Paste Stack"
            case .shortcuts:  return "快捷键"
            case .advanced:   return "高级"
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
        .frame(width: 620, height: 460)
        .background(c.window)
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
        .frame(width: 150, alignment: .topLeading)
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

// MARK: - Reusable segmented control (recessed track + elevated thumb)

struct DSSegmented<Value: Hashable>: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        let c = DSColors(scheme: scheme)
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Text(option.label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? c.text : c.text2)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? c.card : .clear)
                            .shadow(color: selected ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.value }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(c.chip)
        )
    }
}

// MARK: - 外观

private struct AppearanceSection: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "外观")

            SettingRow(label: "主题") {
                DSSegmented(
                    selection: $settings.appearance,
                    options: [("light", "浅色"), ("dark", "深色"), ("system", "跟随系统")]
                )
            }

            SettingRow(label: "强调色", bottom: 0) {
                HStack(spacing: 8) {
                    Circle().fill(c.accent).frame(width: 13, height: 13)
                    Text("跟随系统")
                        .font(.system(size: 12.5))
                        .foregroundColor(c.text2)
                }
            }
        }
    }
}

// MARK: - 历史

private struct HistorySection: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "历史")

            SettingRow(label: "历史上限") {
                DSSegmented(
                    selection: $settings.historyLimit,
                    options: [(50, "50"), (100, "100"), (500, "500"), (1000, "1000")]
                )
            }

            SettingRow(label: "开机启动", bottom: 0) {
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
    private let cells: [(value: String, label: String)] = [
        ("topLeft", "左上"), ("topCenter", "顶部"), ("topRight", "右上"),
        ("bottomLeft", "左下"), ("bottomCenter", "底部"), ("bottomRight", "右下")
    ]

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Paste Stack")

            SettingRow(label: "显示进度浮窗") {
                Toggle("", isOn: $settings.showPasteStackHUD)
                    .toggleStyle(.dsSwitch)
                    .labelsHidden()
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("浮窗位置")
                    .font(.system(size: 13.5))
                    .foregroundColor(c.text)
                positionGrid(c)
                if settings.pasteStackHUDPosition == "custom" {
                    Text("当前为自定义位置（拖拽设定）")
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

// MARK: - 快捷键

private struct ShortcutsSection: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "快捷键")

            shortcutRow("唤起浮层", shortcut: $settings.globalShortcut)
            shortcutRow("截图标注", shortcut: $settings.screenshotShortcut)
            shortcutRow("屏幕取词", shortcut: $settings.textCaptureShortcut)
            shortcutRow("粘贴图片", shortcut: $settings.pasteImageShortcut, bottom: 0)
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

    private func shortcutRow(_ label: String, shortcut: Binding<String>, bottom: CGFloat = 14) -> some View {
        SettingRow(label: label, bottom: bottom) {
            ShortcutRecorder(shortcut: shortcut)
                .frame(width: 200, height: 24)
        }
    }
}

// MARK: - 高级

private struct AdvancedSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "高级")

            VStack(alignment: .leading, spacing: 12) {
                Button("清缓存") {
                    CacheManager.shared.clearAllCaches()
                }
                .dsButton(.secondary)

                Button("清历史") {
                    ClipboardStore.shared.clearAll()
                }
                .dsButton(.destructive)
            }
        }
    }
}
