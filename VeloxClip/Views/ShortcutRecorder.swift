import SwiftUI
import AppKit
import Carbon

struct ShortcutRecorderChrome: Equatable {
    let backgroundWhite: CGFloat
    let backgroundAlpha: CGFloat
    let borderWhite: CGFloat
    let borderAlpha: CGFloat

    init(isDark: Bool) {
        backgroundWhite = isDark ? 1.0 : 0.0
        backgroundAlpha = isDark ? 0.08 : 0.045
        borderWhite = isDark ? 1.0 : 0.0
        borderAlpha = 0.14
    }

    var backgroundColor: NSColor {
        NSColor(white: backgroundWhite, alpha: backgroundAlpha)
    }

    var borderColor: NSColor {
        NSColor(white: borderWhite, alpha: borderAlpha)
    }
}

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
        // No-op, monitor handled in viewWillMove
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopMonitoring()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyButtonChrome()
    }
    
    func updateShortcut(_ newShortcut: String) {
        if !isRecording {
            button?.title = displayShortcut(newShortcut)
        }
    }
    
    private func setupView() {
        let button = NSButton(title: displayShortcut(shortcut), target: self, action: #selector(startRecording))
        // Self-drawn chrome instead of the system rounded bezel (whose corners /
        // padding / shadow differ across macOS versions) so the recorder looks the
        // same on every machine.
        button.isBordered = false
        button.wantsLayer = true
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        self.button = button
        applyButtonChrome()
        updateButton()
    }

    private func applyButtonChrome() {
        guard let button else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let chrome = ShortcutRecorderChrome(isDark: isDark)
        button.layer?.backgroundColor = chrome.backgroundColor.cgColor
        button.layer?.borderColor = chrome.borderColor.cgColor
    }
    
    private var recordingTimeout: Task<Void, Never>?

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
                let isFunctionKey = KeyCodeTable.isFunctionKey(keyCode)
                let hasModifier = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control)
                
                guard isFunctionKey || hasModifier else {
                    // If ESC pressed without modifiers, cancel
                    if keyCode == 53 { // ESC
                        self.cancelRecording()
                    }
                    return event
                }
                
                // Build shortcut string; a key we can't name (e.g. a media key) is
                // ignored rather than committed as a key-less "cmd+shift"
                guard let shortcutString = ShortcutParser.string(modifiers: modifiers, keyCode: keyCode) else {
                    return nil
                }
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
        
        // Cancel recording after 10 seconds. Tied to THIS recording — a stale
        // timer from an earlier, cancelled recording must not kill a new one
        recordingTimeout?.cancel()
        recordingTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, self?.isRecording == true else { return }
            self?.cancelRecording()
        }
    }
    
    private func cancelRecording() {
        isRecording = false
        updateButton()
        stopMonitoring()
    }
    
    private func stopMonitoring() {
        recordingTimeout?.cancel()
        recordingTimeout = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
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
