import Foundation
import AppKit
import SwiftUI

@MainActor
class ScreenshotEditorService: NSObject, NSWindowDelegate {
    static let shared = ScreenshotEditorService()

    private var editorWindow: NSWindow?
    private var eventMonitor: Any?
    private var editorState: EditorState?

    private override init() {
        super.init()
    }

    // Show editor window with image
    func showEditor(with image: NSImage) {
        // Close existing window if any
        closeEditor()

        let state = EditorState()
        editorState = state

        let contentView = ScreenshotEditorView(
            image: image,
            editorState: state,
            onSave: { [weak self] editedImage in
                self?.saveImage(editedImage)
            },
            onDone: { [weak self] editedImage in
                self?.copyToClipboard(editedImage)
                self?.closeEditor()
            },
            onClose: { [weak self] in
                self?.requestClose()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)

        // Calculate window size — scale to the image but keep the toolbar usable;
        // small screenshots no longer force a huge window
        let imageSize = image.size
        let maxWidth: CGFloat = 1600
        let maxHeight: CGFloat = 1000
        let minWidth: CGFloat = 900
        let minHeight: CGFloat = 650
        let scale = min(1.0, min(maxWidth / imageSize.width, maxHeight / imageSize.height))
        let windowSize = NSSize(
            width: max(minWidth, min(imageSize.width * scale, maxWidth) + 120),
            height: max(minHeight, min(imageSize.height * scale, maxHeight) + 180)
        )

        // Create window with default frame (will center it after)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingController.view
        window.title = "Screenshot Editor"
        window.backgroundColor = NSColor(white: 0.95, alpha: 1.0)
        window.level = .normal // Allows save dialog on top
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self // Title-bar close goes through the same confirm/cleanup path

        self.editorWindow = window

        // Make window appear first
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Center window on screen after it's displayed
        DispatchQueue.main.async {
            window.center()
        }

        // Keyboard handling: ESC closes (with confirmation), Cmd+Z / Shift+Cmd+Z undo/redo
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.editorWindow, window.isKeyWindow else { return event }

            // While the text annotation field is being edited, let it handle keys
            // (ESC must not tear down the whole editor mid-typing)
            if window.firstResponder is NSTextView { return event }

            if event.keyCode == 53 { // ESC
                self.requestClose()
                return nil
            }

            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                if event.modifierFlags.contains(.shift) {
                    self.editorState?.redo()
                } else {
                    self.editorState?.undo()
                }
                return nil
            }

            return event
        }
    }

    // Close with confirmation when there are unsaved annotations
    func requestClose() {
        guard let window = editorWindow else { return }
        guard let state = editorState, !state.elements.isEmpty else {
            closeEditor()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Discard annotations?"
        alert.informativeText = "You have unsaved annotations. Closing the editor will discard them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                Task { @MainActor in
                    self?.closeEditor()
                }
            }
        }
    }

    func closeEditor() {
        let window = editorWindow
        cleanup()
        window?.close()
    }

    private func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        editorWindow?.delegate = nil
        editorWindow = nil
        editorState = nil
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let state = editorState, !state.elements.isEmpty else { return true }
        requestClose() // shows the confirmation sheet; closes on confirm
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // Covers any close path that bypasses closeEditor()
        cleanup()
    }

    // MARK: - Output

    private func saveImage(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]

        // Generate filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "Screenshot \(timestamp)"
        savePanel.canCreateDirectories = true

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = savePanel.url else { return }
            Task { @MainActor in
                Self.write(image, to: url)
            }
        }

        if let window = editorWindow {
            savePanel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            savePanel.begin(completionHandler: handleResponse)
        }
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            print("❌ Failed to encode edited image")
            return
        }

        // Honor the extension the user picked in the save panel
        let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let fileType: NSBitmapImageRep.FileType = isJPEG ? .jpeg : .png
        let properties: [NSBitmapImageRep.PropertyKey: Any] = isJPEG ? [.compressionFactor: 0.9] : [:]

        guard let data = bitmapImage.representation(using: fileType, properties: properties) else {
            print("❌ Failed to encode edited image as \(isJPEG ? "JPEG" : "PNG")")
            return
        }

        do {
            try data.write(to: url)
            print("✅ Image saved to: \(url.path)")
        } catch {
            print("❌ Failed to save image: \(error)")
            ErrorHandler.shared.handle(error)
        }
    }

    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Primary method: Write NSImage object directly (most compatible)
        let writeSuccess = pasteboard.writeObjects([image])
        print("✅ Edited image copied to clipboard: \(writeSuccess)")

        // Backup: Also set TIFF representation for compatibility
        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)

            // Convert to PNG properly
            if let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }
        }

        // Intentionally NOT gated as a self-write: the edited image is new
        // content and should be picked up by ClipboardMonitor into history
    }

    func isShowing() -> Bool {
        return editorWindow != nil && editorWindow?.isVisible == true
    }
}
