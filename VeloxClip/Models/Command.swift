import SwiftUI

struct Command: Identifiable, Equatable {
    let id: String
    let title: String
    let keyHint: String?
    let icon: String   // SF Symbol name

    static func == (lhs: Command, rhs: Command) -> Bool { lhs.id == rhs.id }
}

enum CommandResolver {
    /// Context-aware action list for an item of the given clipboard `type`.
    static func commands(forType type: String) -> [Command] {
        var cmds: [Command] = [
            Command(id: "paste", title: "粘贴", keyHint: "⏎",  icon: "doc.on.clipboard"),
            Command(id: "copy",  title: "复制", keyHint: "⌘C", icon: "doc.on.doc"),
        ]
        if type == "color" {
            cmds.append(Command(id: "copyHex", title: "复制 HEX", keyHint: nil, icon: "number"))
            cmds.append(Command(id: "copyRgb", title: "复制 RGB", keyHint: nil, icon: "number"))
        }
        cmds.append(contentsOf: [
            Command(id: "favorite", title: "收藏",            keyHint: nil,     icon: "star"),
            Command(id: "stack",    title: "加入 Paste Stack", keyHint: "space", icon: "square.stack"),
            Command(id: "delete",   title: "删除",            keyHint: "⌫",     icon: "trash"),
        ])
        return cmds
    }
}
