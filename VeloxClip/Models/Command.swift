import SwiftUI

struct Command: Identifiable, Equatable {
    let id: String
    let title: String
    let keyHint: String?
    let icon: String   // SF Symbol name

    // equal by identity; ids are unique within a resolver result
    static func == (lhs: Command, rhs: Command) -> Bool { lhs.id == rhs.id }
}

enum CommandResolver {
    /// Context-aware action list for an item of the given clipboard `type`.
    static func commands(forType type: String, language: AppLanguage = .zhHans) -> [Command] {
        commands(forType: type, content: nil, language: language)
    }

    static func commands(for item: ClipboardItem?, language: AppLanguage = .zhHans) -> [Command] {
        commands(
            forType: item?.type ?? "text",
            content: item?.content,
            language: language
        )
    }

    private static func commands(forType type: String,
                                 content: String?,
                                 language: AppLanguage) -> [Command] {
        var cmds: [Command] = [
            Command(id: "paste",  title: L10n.string("command.paste", language: language), keyHint: "↵",  icon: "doc.on.clipboard"),
            Command(id: "copy",   title: L10n.string("command.copy", language: language), keyHint: "⌘C", icon: "doc.on.doc"),
            Command(id: "detail", title: L10n.string("command.detail", language: language), keyHint: "⌘→",  icon: "doc.text.magnifyingglass"),
        ]
        if type == "image" {
            cmds.append(Command(id: "editImage", title: L10n.string("command.editImage", language: language), keyHint: nil, icon: "pencil"))
        }
        if type == "color" {
            cmds.append(Command(id: "copyHex", title: L10n.string("command.copyHex", language: language), keyHint: nil, icon: "number"))
            cmds.append(Command(id: "copyRgb", title: L10n.string("command.copyRgb", language: language), keyHint: nil, icon: "number"))
        }
        if type == "file", hasFilePaths(content) {
            cmds.append(Command(id: "revealInFinder", title: L10n.string("command.revealInFinder", language: language), keyHint: nil, icon: "folder"))
            cmds.append(Command(id: "copyPath", title: L10n.string("command.copyPath", language: language), keyHint: nil, icon: "doc.on.doc"))
        }
        if isOpenableURLContent(content) {
            cmds.append(Command(id: "openURL", title: L10n.string("command.openURL", language: language), keyHint: nil, icon: "safari"))
        }
        cmds.append(contentsOf: [
            Command(id: "favorite", title: L10n.string("command.favorite", language: language), keyHint: nil,    icon: "star"),
            Command(id: "stack",    title: L10n.string("command.stack", language: language), keyHint: "⌘⏎", icon: "square.stack"),
            Command(id: "delete",   title: L10n.string("command.delete", language: language), keyHint: nil,    icon: "trash"),
        ])
        return cmds
    }

    private static func isOpenableURLContent(_ content: String?) -> Bool {
        guard let content = content?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: content),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func hasFilePaths(_ content: String?) -> Bool {
        guard let content else { return false }
        return !RowPresentation.filePaths(from: content).isEmpty
    }
}
