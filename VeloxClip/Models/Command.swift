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
        var cmds: [Command] = [
            Command(id: "paste",  title: L10n.string("command.paste", language: language), keyHint: "↵",  icon: "doc.on.clipboard"),
            Command(id: "copy",   title: L10n.string("command.copy", language: language), keyHint: "⌘C", icon: "doc.on.doc"),
            Command(id: "detail", title: L10n.string("command.detail", language: language), keyHint: "⌘→",  icon: "doc.text.magnifyingglass"),
        ]
        if type == "color" {
            cmds.append(Command(id: "copyHex", title: L10n.string("command.copyHex", language: language), keyHint: nil, icon: "number"))
            cmds.append(Command(id: "copyRgb", title: L10n.string("command.copyRgb", language: language), keyHint: nil, icon: "number"))
        }
        cmds.append(contentsOf: [
            Command(id: "favorite", title: L10n.string("command.favorite", language: language), keyHint: nil,    icon: "star"),
            Command(id: "stack",    title: L10n.string("command.stack", language: language), keyHint: "⌘⏎", icon: "square.stack"),
            Command(id: "delete",   title: L10n.string("command.delete", language: language), keyHint: nil,    icon: "trash"),
        ])
        return cmds
    }
}
