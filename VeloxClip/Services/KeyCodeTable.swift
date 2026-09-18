import AppKit
import Carbon

/// Single source of truth for virtual key code ↔ name, shared by the recorder
/// (event → string) and the hotkey manager (string → RegisterEventHotKey).
/// Values are the Carbon `kVK_*` constants; the two hand-maintained tables this
/// replaces disagreed on `[`, `\` and `-`.
enum KeyCodeTable {
    static let namesByCode: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_F): "f",
        UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_Z): "z", UInt16(kVK_ANSI_X): "x",
        UInt16(kVK_ANSI_C): "c", UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_Q): "q",
        UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_R): "r", UInt16(kVK_ANSI_Y): "y",
        UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_O): "o", UInt16(kVK_ANSI_U): "u", UInt16(kVK_ANSI_I): "i",
        UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_L): "l", UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k",
        UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_M): "m",

        UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5", UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9", UInt16(kVK_ANSI_0): "0",

        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]", UInt16(kVK_ANSI_Backslash): "\\",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Semicolon): ";", UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Slash): "/", UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Grave): "`",

        UInt16(kVK_Return): "return", UInt16(kVK_Tab): "tab", UInt16(kVK_Space): "space",
        UInt16(kVK_Delete): "delete", UInt16(kVK_Escape): "escape",
        UInt16(kVK_LeftArrow): "left", UInt16(kVK_RightArrow): "right",
        UInt16(kVK_DownArrow): "down", UInt16(kVK_UpArrow): "up",

        UInt16(kVK_F1): "f1", UInt16(kVK_F2): "f2", UInt16(kVK_F3): "f3", UInt16(kVK_F4): "f4",
        UInt16(kVK_F5): "f5", UInt16(kVK_F6): "f6", UInt16(kVK_F7): "f7", UInt16(kVK_F8): "f8",
        UInt16(kVK_F9): "f9", UInt16(kVK_F10): "f10", UInt16(kVK_F11): "f11", UInt16(kVK_F12): "f12",
    ]

    private static let codesByName: [String: UInt16] = {
        var map = Dictionary(uniqueKeysWithValues: namesByCode.map { ($1, $0) })
        // Aliases accepted in stored strings
        map["enter"] = UInt16(kVK_Return)
        map["backspace"] = UInt16(kVK_Delete)
        map["esc"] = UInt16(kVK_Escape)
        map["\""] = UInt16(kVK_ANSI_Quote)
        return map
    }()

    private static let functionKeyCodes: Set<UInt16> = Set(
        [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].map(UInt16.init)
    )

    static func name(for code: UInt16) -> String? { namesByCode[code] }
    static func code(for name: String) -> UInt16? { codesByName[name.lowercased()] }
    static func isFunctionKey(_ code: UInt16) -> Bool { functionKeyCodes.contains(code) }
}

/// Stored shortcut string format: lowercase parts joined by "+", e.g. "cmd+shift+v", "f1".
enum ShortcutParser {
    struct Parsed: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32   // Carbon modifier mask for RegisterEventHotKey
    }

    static func parse(_ string: String) -> Parsed? {
        let parts = string.lowercased()
            .components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyName: String?
        for part in parts {
            switch part {
            case "cmd", "command", "⌘":   modifiers |= UInt32(cmdKey)
            case "shift", "⇧":            modifiers |= UInt32(shiftKey)
            case "alt", "option", "⌥":    modifiers |= UInt32(optionKey)
            case "ctrl", "control", "⌃":  modifiers |= UInt32(controlKey)
            default:
                guard keyName == nil else { return nil } // two non-modifier parts
                keyName = part
            }
        }
        guard let keyName, let code = KeyCodeTable.code(for: keyName) else { return nil }
        return Parsed(keyCode: UInt32(code), modifiers: modifiers)
    }

    /// Recorder side: nil when the key has no name, so the caller keeps waiting
    /// instead of committing a key-less "cmd+shift".
    static func string(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String? {
        guard let keyName = KeyCodeTable.name(for: keyCode) else { return nil }
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift)   { parts.append("shift") }
        if modifiers.contains(.option)  { parts.append("alt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
}
