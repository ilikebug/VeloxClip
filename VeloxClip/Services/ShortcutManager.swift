import AppKit
import Carbon

@MainActor
class ShortcutManager {
    static let shared = ShortcutManager()
    
    // Store multiple hotkey references by ID
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    
    // Hotkey IDs
    private let windowToggleID: UInt32 = 1
    private let screenshotID: UInt32 = 2
    private let pasteImageID: UInt32 = 3
    
    // Note: As a singleton, this object is never deallocated during app lifetime
    // Resources are automatically cleaned up by the system when the app terminates
    
    func registerAllShortcuts() {
        registerGlobalShortcut()
        registerScreenshotShortcut()
        registerPasteImageShortcut()
    }
    
    func registerGlobalShortcut() {
        let shortcutString = AppSettings.shared.globalShortcut
        registerShortcut(shortcutString, id: windowToggleID, action: {
            WindowManager.shared.toggleWindow()
        })
    }
    
    func registerScreenshotShortcut() {
        let shortcutString = AppSettings.shared.screenshotShortcut
        registerShortcut(shortcutString, id: screenshotID, action: {
            ScreenshotService.shared.captureArea()
        })
    }
    
    func registerPasteImageShortcut() {
        let shortcutString = AppSettings.shared.pasteImageShortcut
        registerShortcut(shortcutString, id: pasteImageID, action: {
            PasteImageService.shared.showPasteImage()
        })
    }
    
    func updateShortcut(_ shortcutString: String) {
        unregisterShortcut(id: windowToggleID)
        registerShortcut(shortcutString, id: windowToggleID, action: {
            WindowManager.shared.toggleWindow()
        })
    }
    
    func updateScreenshotShortcut(_ shortcutString: String) {
        unregisterShortcut(id: screenshotID)
        registerShortcut(shortcutString, id: screenshotID, action: {
            ScreenshotService.shared.captureArea()
        })
    }
    
    func updatePasteImageShortcut(_ shortcutString: String) {
        unregisterShortcut(id: pasteImageID)
        registerShortcut(shortcutString, id: pasteImageID, action: {
            PasteImageService.shared.showPasteImage()
        })
    }
    
    private func unregisterShortcut(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
    }
    
    private func registerShortcut(_ shortcutString: String, id: UInt32, action: @escaping () -> Void) {
        // Parse shortcut string
        let (keyCode, modifiers): (UInt32, UInt32)
        
        if let parsed = parseShortcut(shortcutString) {
            keyCode = parsed.0
            modifiers = parsed.1
        } else {
            // Fallback: if parsing fails, try to handle function keys without modifiers
            if let funcKeyCode = parseFunctionKey(shortcutString) {
                keyCode = funcKeyCode
                modifiers = 0 // Function keys can be used without modifiers
            } else {
                print("Failed to parse shortcut: \(shortcutString)")
                return
            }
        }
        
        // Setup event handler if not already set
        if eventHandler == nil {
            var eventType = EventTypeSpec()
            eventType.eventClass = OSType(kEventClassKeyboard)
            eventType.eventKind = UInt32(kEventHotKeyPressed)
            
            var handler: EventHandlerRef?
            InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if err == noErr {
                    DispatchQueue.main.async {
                        if hotKeyID.id == 1 {
                            WindowManager.shared.toggleWindow()
                        } else if hotKeyID.id == 2 {
                            ScreenshotService.shared.captureArea()
                        } else if hotKeyID.id == 3 {
                            PasteImageService.shared.showPasteImage()
                        }
                    }
                }
                return noErr
            }, 1, &eventType, nil, &handler)
            
            eventHandler = handler
        }
        
        // Register the hotkey
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564c5843) // 'VLXC'
        hotKeyID.id = id
        
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        
        if status == noErr {
            hotKeyRefs[id] = ref
        } else {
            print("Failed to register hotkey \(id) with shortcut \(shortcutString), status: \(status)")
        }
    }
    
    private func parseShortcut(_ shortcutString: String) -> (UInt32, UInt32)? {
        let parts = shortcutString.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Allow single key (for function keys) or modifier + key
        guard !parts.isEmpty else { return nil }
        
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
        
        guard !keyChar.isEmpty else { return nil }
        
        // Convert character to key code
        guard let keyCode = stringToKeyCode(keyChar) else {
            return nil
        }
        
        return (UInt32(keyCode), modifiers)
    }
    
    // Parse function keys (F1-F12) without modifiers
    private func parseFunctionKey(_ shortcutString: String) -> UInt32? {
        let lowercased = shortcutString.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Function keys F1-F12
        let functionKeyMap: [String: UInt32] = [
            "f1": 122, "f2": 120, "f3": 99, "f4": 118,
            "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111
        ]
        
        return functionKeyMap[lowercased]
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
            "'": 39, "\"": 39, ";": 41, ",": 43, "/": 44, ".": 47, "`": 50,
            // Function keys F1-F12
            "f1": 122, "f2": 120, "f3": 99, "f4": 118,
            "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111
        ]
        
        return keyMap[key.lowercased()]
    }
}
