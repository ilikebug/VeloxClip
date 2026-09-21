import AppKit
import Carbon

/// Global (Carbon) hotkeys.
///
/// The manager knows how to register key combinations and nothing about what
/// they do. It used to dispatch a hardcoded if/else over magic integers
/// straight into `WindowManager` (App layer) and three sibling services, which
/// made Services' inbound entry point a hub coupling everything to everything —
/// and made the manager impossible to construct in a test. The App layer wires
/// shortcut → behaviour now; see `AppDelegate.registerShortcuts`.
@MainActor
class ShortcutManager {
    static let shared = ShortcutManager()

    /// Identifies a registered hotkey. Typed so the dispatch table can't be
    /// indexed with a stray integer.
    enum Slot: UInt32, CaseIterable {
        case windowToggle = 1
        case screenshot = 2
        case pasteImage = 3
        case textCapture = 4
    }

    private var hotKeyRefs: [Slot: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    /// The Carbon callback is a C function pointer: it can't capture context,
    /// so it looks the action up here.
    private nonisolated(unsafe) static var dispatchTable: [UInt32: () -> Void] = [:]

    // Note: As a singleton, this object is never deallocated during app lifetime
    // Resources are automatically cleaned up by the system when the app terminates

    /// Registers `shortcut` for `slot` and remembers what it should do.
    func register(_ shortcut: String, for slot: Slot, action: @escaping () -> Void) {
        actions[slot.rawValue] = action
        Self.dispatchTable[slot.rawValue] = action
        registerShortcut(shortcut, slot: slot)
    }

    /// Re-binds an already-registered slot to a new key combination, keeping
    /// its action.
    ///
    /// Validates BEFORE unregistering: an unparseable string used to drop the
    /// working hotkey and leave the user with nothing.
    func update(_ shortcut: String, for slot: Slot) {
        guard ShortcutParser.parse(shortcut) != nil else {
            print("Ignoring unparseable shortcut \"\(shortcut)\" for hotkey \(slot); keeping the current one")
            return
        }
        unregisterShortcut(slot: slot)
        registerShortcut(shortcut, slot: slot)
    }

    /// True when `slot` currently has a live registration.
    func isRegistered(_ slot: Slot) -> Bool {
        hotKeyRefs[slot] != nil
    }

    private func unregisterShortcut(slot: Slot) {
        if let ref = hotKeyRefs[slot] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: slot)
        }
    }

    private func registerShortcut(_ shortcutString: String, slot: Slot) {
        guard let parsed = ShortcutParser.parse(shortcutString) else {
            print("Failed to parse shortcut: \(shortcutString)")
            return
        }

        installEventHandlerIfNeeded()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564c5843) // 'VLXC'
        hotKeyID.id = slot.rawValue

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(parsed.keyCode, parsed.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)

        if status == noErr {
            hotKeyRefs[slot] = ref
        } else {
            // The user configured this shortcut in Preferences and it silently
            // did nothing — they must be told, not just the console.
            print("Failed to register hotkey \(slot) with shortcut \(shortcutString), status: \(status)")
            ErrorHandler.shared.handle(ShortcutError.registrationFailed(shortcut: shortcutString, status: status))
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        var handler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { (_, theEvent, _) -> OSStatus in
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
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    // Looked up, not hardcoded: Services no longer names
                    // WindowManager or any sibling service.
                    ShortcutManager.dispatchTable[id]?()
                }
            }
            return noErr
        }, 1, &eventType, nil, &handler)

        eventHandler = handler
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
