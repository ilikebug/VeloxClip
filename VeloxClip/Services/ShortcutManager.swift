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
    private let textCaptureID: UInt32 = 4

    // Note: As a singleton, this object is never deallocated during app lifetime
    // Resources are automatically cleaned up by the system when the app terminates

    func registerAllShortcuts() {
        registerGlobalShortcut()
        registerScreenshotShortcut()
        registerPasteImageShortcut()
        registerTextCaptureShortcut()
    }

    func registerTextCaptureShortcut() {
        registerShortcut(AppSettings.shared.textCaptureShortcut, id: textCaptureID)
    }

    func updateTextCaptureShortcut(_ shortcutString: String) {
        replaceShortcut(shortcutString, id: textCaptureID)
    }

    func registerGlobalShortcut() {
        registerShortcut(AppSettings.shared.globalShortcut, id: windowToggleID)
    }

    func registerScreenshotShortcut() {
        registerShortcut(AppSettings.shared.screenshotShortcut, id: screenshotID)
    }

    func registerPasteImageShortcut() {
        registerShortcut(AppSettings.shared.pasteImageShortcut, id: pasteImageID)
    }

    func updateShortcut(_ shortcutString: String) {
        replaceShortcut(shortcutString, id: windowToggleID)
    }

    func updateScreenshotShortcut(_ shortcutString: String) {
        replaceShortcut(shortcutString, id: screenshotID)
    }

    func updatePasteImageShortcut(_ shortcutString: String) {
        replaceShortcut(shortcutString, id: pasteImageID)
    }

    // Validate BEFORE unregistering: an unparseable string used to drop the
    // working hotkey and leave the user with nothing.
    private func replaceShortcut(_ shortcutString: String, id: UInt32) {
        guard ShortcutParser.parse(shortcutString) != nil else {
            print("Ignoring unparseable shortcut \"\(shortcutString)\" for hotkey \(id); keeping the current one")
            return
        }
        unregisterShortcut(id: id)
        registerShortcut(shortcutString, id: id)
    }

    private func unregisterShortcut(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
    }

    private func registerShortcut(_ shortcutString: String, id: UInt32) {
        guard let parsed = ShortcutParser.parse(shortcutString) else {
            print("Failed to parse shortcut: \(shortcutString)")
            return
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
                        } else if hotKeyID.id == 4 {
                            TextCaptureService.shared.captureText()
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
        let status = RegisterEventHotKey(parsed.keyCode, parsed.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)

        if status == noErr {
            hotKeyRefs[id] = ref
        } else {
            // The user configured this shortcut in Preferences and it silently
            // did nothing — they must be told, not just the console.
            print("Failed to register hotkey \(id) with shortcut \(shortcutString), status: \(status)")
            ErrorHandler.shared.handle(ShortcutError.registrationFailed(shortcut: shortcutString, status: status))
        }
    }
}

enum ShortcutError: LocalizedError {
    case registrationFailed(shortcut: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let shortcut, let status):
            return "Could not register the shortcut \(shortcut) (error \(status)). Another app may already be using it."
        }
    }
}
