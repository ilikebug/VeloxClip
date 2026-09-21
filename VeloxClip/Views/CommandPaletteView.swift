import SwiftUI

/// ⌘K command palette — a centered floating panel listing type-aware actions
/// for the currently selected clipboard item. Token-only styling.
struct CommandPaletteView: View {
    @Environment(\.colorScheme) private var scheme
    let item: ClipboardItem?
    var isDetailPresented: Bool = false
    let onExecute: (Command) -> Void
    let onClose: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var filter: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool
    // Last hover sample (window coords). The palette appears centred, usually
    // under a resting cursor; only real movement may re-target the highlight.
    @State private var lastHoverLocation: CGPoint?

    private var allCommands: [Command] {
        CommandResolver.commands(for: item, isDetailPresented: isDetailPresented, language: settings.appLanguage)
    }

    // While an input method is composing (marked text), ⏎/Esc belong to it
    private var isComposingText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private var filteredCommands: [Command] {
        guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else { return allCommands }
        return allCommands.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    /// Parsed color for a color item (from its hex `content`); nil otherwise.
    private var itemColor: Color? {
        guard item?.type == "color", let content = item?.content else { return nil }
        return Color(clipboardColor: content)
    }

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(spacing: 0) {
            header(c)
            Divider().overlay(c.divider)
            commandList(c)
        }
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(c.divider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: DesignSystem.panelShadow(scheme), radius: 25, y: 18)
        .onAppear { fieldFocused = true }
        .onChange(of: filter) { _, _ in
            // Keep selection valid as the list shrinks/grows
            if selectedIndex >= filteredCommands.count {
                selectedIndex = max(0, filteredCommands.count - 1)
            }
        }
        .onKeyPress(.upArrow) {
            if !filteredCommands.isEmpty {
                selectedIndex = max(0, selectedIndex - 1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !filteredCommands.isEmpty {
                selectedIndex = min(filteredCommands.count - 1, selectedIndex + 1)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if isComposingText { return .ignored }
            if filteredCommands.indices.contains(selectedIndex) {
                onExecute(filteredCommands[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if isComposingText { return .ignored }
            onClose()
            return .handled
        }
    }

    // MARK: Header

    @ViewBuilder private func header(_ c: DSColors) -> some View {
        VStack(spacing: 9) {
            summaryChip(c)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(L10n.string("command.search.placeholder", language: settings.appLanguage), text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundColor(c.text)
                .focused($fieldFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func summaryChip(_ c: DSColors) -> some View {
        HStack(spacing: 7) {
            if let color = itemColor {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(item?.content ?? "")
            } else {
                Image(systemName: typeIcon)
                    .font(.system(size: 10))
                Text(typeLabel)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(c.text2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(c.chip)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var typeIcon: String {
        switch item?.type {
        case "image": return "photo"
        case "file":  return "doc"
        case "rtf":   return "doc.richtext"
        case "color": return "paintpalette"
        default:      return "textformat"
        }
    }

    private var typeLabel: String {
        guard let item else { return L10n.string("command.noSelection", language: settings.appLanguage) }
        return item.localizedTypeName(language: settings.appLanguage)
    }

    // MARK: Command list

    /// Command ids that form the destructive/management group; a divider is
    /// inserted before the first of these that appears.
    private static let groupBoundaryIDs: Set<CommandKind> = [.favorite, .stack, .delete]

    @ViewBuilder private func commandList(_ c: DSColors) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, cmd in
                // Divider before the first command of the destructive group
                if Self.groupBoundaryIDs.contains(cmd.id),
                   index > 0, !Self.groupBoundaryIDs.contains(filteredCommands[index - 1].id) {
                    Rectangle()
                        .fill(c.divider)
                        .frame(height: 0.5)
                        .padding(.vertical, 4)
                }
                commandRow(cmd, isSelected: index == selectedIndex, c: c)
                    // Mouse movement moves the highlight just like ↑↓ do, so ⏎ and
                    // click agree. The first sample (palette appearing under the
                    // cursor) is ignored, or an immediate ⏎ could hit e.g. Delete.
                    .onContinuousHover(coordinateSpace: .global) { phase in
                        guard case .active(let location) = phase else { return }
                        if let last = lastHoverLocation, last != location {
                            selectedIndex = index
                        }
                        lastHoverLocation = location
                    }
                    .onTapGesture { onExecute(cmd) }
            }
        }
        .padding(6)
    }

    @ViewBuilder private func commandRow(_ cmd: Command, isSelected: Bool, c: DSColors) -> some View {
        let isDelete = cmd.kind == .delete
        let titleColor: Color = isSelected ? .white : (isDelete ? c.destructive : c.text)
        HStack(spacing: 11) {
            if (cmd.kind == .copyHex || cmd.kind == .copyRgb), let color = itemColor {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: cmd.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : (isDelete ? c.destructive : c.text))
                    .frame(width: 13, height: 13)
            }
            Text(cmd.title)
                .font(.system(size: 13.5))
                .foregroundColor(titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Computed color value for HEX/RGB rows; keyHint badge otherwise.
            if let value = computedValue(for: cmd) {
                Text(value)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(isSelected ? .white : c.text3)
            } else if let key = cmd.keyHint {
                let role: DSKeyBadge.Role = isSelected ? .onAccent : (isDelete ? .destructive : .standard)
                DSKeyBadge(label: key, role: role)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? c.accent : Color.clear)
        )
        .contentShape(Rectangle())
    }

    /// Trailing computed value for the color copy rows (e.g. `#0A84FF`, `10 132 255`).
    private func computedValue(for cmd: Command) -> String? {
        guard let content = item?.content else { return nil }
        switch cmd.kind {
        case .copyHex: return ColorFormatting.hex(from: content)
        case .copyRgb: return ColorFormatting.rgb(from: content)
        default:       return nil
        }
    }
}
