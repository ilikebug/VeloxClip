import SwiftUI
import AppKit
import Carbon

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: String
    
    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(shortcut: $shortcut)
        return view
    }
    
    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.updateShortcut(shortcut)
    }
}

class ShortcutRecorderView: NSView {
    @Binding var shortcut: String
    private var button: NSButton?
    private var isRecording = false
    private var eventMonitor: Any?
    
    init(shortcut: Binding<String>) {
        self._shortcut = shortcut
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopMonitoring()
    }
    
    func updateShortcut(_ newShortcut: String) {
        if !isRecording {
            button?.title = displayShortcut(newShortcut)
        }
    }
    
    private func setupView() {
        let button = NSButton(title: displayShortcut(shortcut), target: self, action: #selector(startRecording))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        self.button = button
        updateButton()
    }
    
    @objc private func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        updateButton()
        
        // Start monitoring key events globally
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            
            if event.type == .keyDown {
                let modifiers = event.modifierFlags
                let keyCode = event.keyCode
                
                // Allow function keys (F1-F12) without modifiers, or require at least one modifier for other keys
                let isFunctionKey = self.isFunctionKey(keyCode)
                let hasModifier = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control)
                
                guard isFunctionKey || hasModifier else {
                    // If ESC pressed without modifiers, cancel
                    if keyCode == 53 { // ESC
                        self.cancelRecording()
                    }
                    return event
                }
                
                // Build shortcut string
                let shortcutString = self.buildShortcutString(modifiers: modifiers, keyCode: keyCode)
                self.shortcut = shortcutString
                self.isRecording = false
                self.updateButton()
                self.stopMonitoring()
                
                // The binding will trigger onChange in SettingsView to update the shortcut
                
                return nil // Consume the event
            } else if event.type == .flagsChanged {
                // Handle modifier-only presses (for display)
                return event
            }
            
            return event
        }
        
        // Cancel recording after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            if self?.isRecording == true {
                self?.cancelRecording()
            }
        }
    }
    
    private func cancelRecording() {
        isRecording = false
        updateButton()
        stopMonitoring()
    }
    
    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func buildShortcutString(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.command) {
            parts.append("cmd")
        }
        if modifiers.contains(.shift) {
            parts.append("shift")
        }
        if modifiers.contains(.option) {
            parts.append("alt")
        }
        if modifiers.contains(.control) {
            parts.append("ctrl")
        }
        
        // Convert keyCode to character
        if let keyChar = keyCodeToString(keyCode) {
            parts.append(keyChar.lowercased())
        }
        
        // If no modifiers, return just the key (for function keys)
        if parts.count == 1 {
            return parts[0]
        }
        
        return parts.joined(separator: "+")
    }
    
    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        // Function keys F1-F12 key codes
        let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        return functionKeyCodes.contains(keyCode)
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        // Map common key codes to characters
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m", 36: "return", 48: "tab",
            49: "space", 51: "delete", 53: "escape", 123: "left", 124: "right",
            125: "down", 126: "up", 27: "[", 30: "]", 33: "\\", 39: "'",
            41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            // Function keys F1-F12
            122: "f1", 120: "f2", 99: "f3", 118: "f4",
            96: "f5", 97: "f6", 98: "f7", 100: "f8",
            101: "f9", 109: "f10", 103: "f11", 111: "f12"
        ]
        
        return keyMap[keyCode]
    }
    
    private func displayShortcut(_ shortcut: String) -> String {
        if shortcut.isEmpty {
            return "Click to record"
        }
        return shortcut.replacingOccurrences(of: "+", with: " + ").uppercased()
    }
    
    private func updateButton() {
        if let button = button {
            if isRecording {
                button.title = "Press keys... (ESC to cancel)"
                button.contentTintColor = .systemRed
            } else {
                button.title = displayShortcut(shortcut)
                button.contentTintColor = nil
            }
        }
    }
}

