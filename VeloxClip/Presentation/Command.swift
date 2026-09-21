import Foundation

/// The actions the command palette can offer.
///
/// Was a bare `String` id, so `MainView.executeCommand` switched over string
/// literals with a `default: break` — a typo compiled fine and silently did
/// nothing, and adding a command gave no compiler prompt to handle it.
enum CommandKind: String, CaseIterable {
    case paste
    case copy
    case detail
    case editImage
    case copyHex
    case copyRgb
    case revealInFinder
    case copyPath
    case openURL
    case favorite
    case stack
    case delete
}

struct Command: Identifiable, Equatable {
    let kind: CommandKind
    let title: String
    let keyHint: String?
    let icon: String   // SF Symbol name

    var id: CommandKind { kind }

    // equal by identity; kinds are unique within a resolver result
    static func == (lhs: Command, rhs: Command) -> Bool { lhs.kind == rhs.kind }
}

enum CommandResolver {
    /// Context-aware action list for an item of the given clipboard `type`.
    static func commands(forType type: String, language: AppLanguage = .zhHans) -> [Command] {
        commands(forType: type, content: nil, language: language)
    }

    /// `isDetailPresented`: the palette opened from the detail pane — "Detail" is a no-op there.
    static func commands(for item: ClipboardItem?,
                         isDetailPresented: Bool = false,
                         language: AppLanguage = .zhHans) -> [Command] {
        commands(
            forType: item?.type ?? "text",
            content: item?.content,
            isDetailPresented: isDetailPresented,
            language: language
        )
    }

    private static func commands(forType type: String,
                                 content: String?,
                                 isDetailPresented: Bool = false,
                                 language: AppLanguage) -> [Command] {
        var cmds: [Command] = [
            Command(kind: .paste,  title: L10n.string("command.paste", language: language), keyHint: "↵",  icon: "doc.on.clipboard"),
            Command(kind: .copy,   title: L10n.string("command.copy", language: language), keyHint: "⌘C", icon: "doc.on.doc"),
        ]
        if !isDetailPresented {
            cmds.append(Command(kind: .detail, title: L10n.string("command.detail", language: language), keyHint: "⌘→",  icon: "doc.text.magnifyingglass"))
        }
        if type == "image" {
            cmds.append(Command(kind: .editImage, title: L10n.string("command.editImage", language: language), keyHint: nil, icon: "pencil"))
        }
        if type == "color" {
            cmds.append(Command(kind: .copyHex, title: L10n.string("command.copyHex", language: language), keyHint: nil, icon: "number"))
            cmds.append(Command(kind: .copyRgb, title: L10n.string("command.copyRgb", language: language), keyHint: nil, icon: "number"))
        }
        if type == "file", hasFilePaths(content) {
            cmds.append(Command(kind: .revealInFinder, title: L10n.string("command.revealInFinder", language: language), keyHint: nil, icon: "folder"))
            cmds.append(Command(kind: .copyPath, title: L10n.string("command.copyPath", language: language), keyHint: nil, icon: "doc.on.doc"))
        }
        if WebURL.isOpenable(content) {
            cmds.append(Command(kind: .openURL, title: L10n.string("command.openURL", language: language), keyHint: nil, icon: "safari"))
        }
        cmds.append(contentsOf: [
            Command(kind: .favorite, title: L10n.string("command.favorite", language: language), keyHint: nil,    icon: "star"),
            Command(kind: .stack,    title: L10n.string("command.stack", language: language), keyHint: "⌘⏎", icon: "square.stack"),
            Command(kind: .delete,   title: L10n.string("command.delete", language: language), keyHint: nil,    icon: "trash"),
        ])
        return cmds
    }

    private static func hasFilePaths(_ content: String?) -> Bool {
        guard let content else { return false }
        return !ClipboardItem.filePaths(from: content).isEmpty
    }
}
