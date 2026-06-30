import SwiftUI

/// ⌘K command palette — a centered floating panel listing type-aware actions
/// for the currently selected clipboard item. Token-only styling.
struct CommandPaletteView: View {
    @Environment(\.colorScheme) private var scheme
    let item: ClipboardItem?
    let onExecute: (Command) -> Void
    let onClose: () -> Void

    @State private var filter: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    private var allCommands: [Command] {
        CommandResolver.commands(forType: item?.type ?? "text")
    }

    private var filteredCommands: [Command] {
        guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else { return allCommands }
        return allCommands.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    /// Parsed color for a color item (from its hex `content`); nil otherwise.
    private var itemColor: Color? {
        guard item?.type == "color", let hex = item?.content else { return nil }
        return Color(hex: hex)
    }

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(spacing: 0) {
            header(c)
            Divider().overlay(c.divider)
            commandList(c)
        }
        .frame(width: 360)
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
            if filteredCommands.indices.contains(selectedIndex) {
                onExecute(filteredCommands[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    // MARK: Header

    @ViewBuilder private func header(_ c: DSColors) -> some View {
        VStack(spacing: 9) {
            summaryChip(c)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("动作…", text: $filter)
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
        guard let item else { return "无选中项" }
        return item.localizedTypeName
    }

    // MARK: Command list

    @ViewBuilder private func commandList(_ c: DSColors) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, cmd in
                commandRow(cmd, isSelected: index == selectedIndex, c: c)
                    .onTapGesture { onExecute(cmd) }
            }
        }
        .padding(6)
    }

    @ViewBuilder private func commandRow(_ cmd: Command, isSelected: Bool, c: DSColors) -> some View {
        HStack(spacing: 11) {
            if (cmd.id == "copyHex" || cmd.id == "copyRgb"), let color = itemColor {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: cmd.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : c.text)
                    .frame(width: 13, height: 13)
            }
            Text(cmd.title)
                .font(.system(size: 13.5))
                .foregroundColor(isSelected ? .white : c.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let key = cmd.keyHint {
                DSKeyBadge(label: key, onAccent: isSelected)
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
}
