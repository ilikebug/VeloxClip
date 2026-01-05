import AppKit
import Carbon

@MainActor
class ShortcutManager {
    static let shared = ShortcutManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    // Note: As a singleton, this object is never deallocated during app lifetime
    // Resources are automatically cleaned up by the system when the app terminates
    
    func registerGlobalShortcut() {
        let shortcutString = AppSettings.shared.globalShortcut
        registerShortcut(shortcutString)
    }
    
    func updateShortcut(_ shortcutString: String) {
        unregisterShortcut()
        registerShortcut(shortcutString)
    }
    
    private func unregisterShortcut() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    private func registerShortcut(_ shortcutString: String) {
        guard let (keyCode, modifiers) = parseShortcut(shortcutString) else {
            // Fallback to default
            registerDefaultShortcut()
            return
        }
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564c5843) // 'VLXC'
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        // Remove old handler if exists
        if let oldHandler = eventHandler {
            RemoveEventHandler(oldHandler)
            eventHandler = nil
        }
        
        var handler: EventHandlerRef?
        // Pass nil as userData since the callback doesn't use it
        // This avoids potential memory management issues with passUnretained
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            DispatchQueue.main.async {
                WindowManager.shared.toggleWindow()
            }
            return noErr
        }, 1, &eventType, nil, &handler)
        
        eventHandler = handler
        
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        
        if status == noErr {
            hotKeyRef = ref
        } else {
            // Fallback to default
            registerDefaultShortcut()
        }
    }
    
    private func registerDefaultShortcut() {
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(9) // V key code is 9
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564c5843)
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        // Remove old handler if exists
        if let oldHandler = eventHandler {
            RemoveEventHandler(oldHandler)
            eventHandler = nil
        }
        
        var handler: EventHandlerRef?
        // Pass nil as userData since the callback doesn't use it
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            DispatchQueue.main.async {
                WindowManager.shared.toggleWindow()
            }
            return noErr
        }, 1, &eventType, nil, &handler)
        
        eventHandler = handler
        
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
    }
    
    private func parseShortcut(_ shortcutString: String) -> (UInt32, UInt32)? {
        let parts = shortcutString.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        
        guard parts.count >= 2 else { return nil } // Need at least modifier + key
        
        var modifiers: UInt32 = 0
        var keyChar: String = ""
        
        for part in parts {
            switch part {
            case "cmd", "command", "⌘":
                modifiers |= UInt32(cmdKey)
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
            case "alt", "option", "⌥":
                modifiers |= UInt32(optionKey)
            case "ctrl", "control", "⌃":
                modifiers |= UInt32(controlKey)
            default:
                keyChar = part
            }
        }
        
        guard !keyChar.isEmpty, modifiers != 0 else { return nil }
        
        // Convert character to key code
        guard let keyCode = stringToKeyCode(keyChar) else {
            return nil
        }
        
        return (UInt32(keyCode), modifiers)
    }
    
    private func stringToKeyCode(_ key: String) -> UInt16? {
        let keyMap: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
            "j": 38, "k": 40, "n": 45, "m": 46, "return": 36, "enter": 36,
            "tab": 48, "space": 49, "delete": 51, "backspace": 51,
            "escape": 53, "esc": 53, "left": 123, "right": 124,
            "down": 125, "up": 126, "[": 27, "]": 30, "\\": 33,
            "'": 39, "\"": 39, ";": 41, ",": 43, "/": 44, ".": 47, "`": 50
        ]
        
        return keyMap[key.lowercased()]
    }
}
