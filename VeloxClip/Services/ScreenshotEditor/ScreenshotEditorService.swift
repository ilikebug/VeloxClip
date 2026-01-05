import Foundation
import AppKit
import SwiftUI

@MainActor
class ScreenshotEditorService {
    static let shared = ScreenshotEditorService()
    
    private var editorWindow: NSWindow?
    private var eventMonitor: Any?
    
    private init() {}
    
    // Show editor window with image
    func showEditor(with image: NSImage) {
        // Close existing window if any
        closeEditor()
        
        let contentView = ScreenshotEditorView(
            image: image,
            onSave: { [weak self] editedImage in
                self?.saveImage(editedImage)
            },
            onCopy: { [weak self] editedImage in
                self?.copyToClipboard(editedImage)
            },
            onCancel: { [weak self] in
                self?.closeEditor()
            }
        )
        
        let hostingController = NSHostingController(rootView: contentView)
        
        // Calculate window size - larger window for better editing experience
        let imageSize = image.size
        let maxWidth: CGFloat = 1600  // Increased from 1200
        let maxHeight: CGFloat = 1000  // Increased from 800
        let minWidth: CGFloat = 1200   // Minimum width to show all tools
        let minHeight: CGFloat = 800   // Minimum height to show all tools
        let scale = min(1.0, min(maxWidth / imageSize.width, maxHeight / imageSize.height))
        let windowSize = NSSize(
            width: max(minWidth, min(imageSize.width * scale, maxWidth) + 120),  // Ensure minimum width
            height: max(minHeight, min(imageSize.height * scale, maxHeight) + 180)  // Ensure minimum height
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
        window.backgroundColor = NSColor(white: 0.95, alpha: 1.0)  // Light gray background
        window.level = .normal  // Changed from .floating to allow save dialog on top
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        
        self.editorWindow = window
        
        // Make window appear first
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Center window on screen after it's displayed
        // Use DispatchQueue to ensure window is fully initialized
        DispatchQueue.main.async {
            window.center()
        }
        
        // Monitor ESC key
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // ESC
                self.closeEditor()
                return nil
            }
            return event
        }
    }
    
    func closeEditor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        editorWindow?.close()
        editorWindow = nil
    }
    
    private func saveImage(_ image: NSImage) {
        // Temporarily lower window level to allow save dialog on top
        let originalLevel = editorWindow?.level
        editorWindow?.level = .normal
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        
        // Generate filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "Screenshot \(timestamp)"
        savePanel.canCreateDirectories = true
        
        // Use beginSheetModal to ensure it appears above the editor window
        if let window = editorWindow {
            savePanel.beginSheetModal(for: window) { response in
                // Restore original window level after dialog closes
                if let originalLevel = originalLevel {
                    self.editorWindow?.level = originalLevel
                }
                
                if response == .OK, let url = savePanel.url {
                    if let tiffData = image.tiffRepresentation,
                       let bitmapImage = NSBitmapImageRep(data: tiffData) {
                        let pngData = bitmapImage.representation(using: .png, properties: [:])
                        do {
                            try pngData?.write(to: url)
                            print("✅ Image saved to: \(url.path)")
                        } catch {
                            print("❌ Failed to save image: \(error)")
                            ErrorHandler.shared.handle(error)
                        }
                    }
                }
            }
        } else {
            // Fallback if window is nil
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    if let tiffData = image.tiffRepresentation,
                       let bitmapImage = NSBitmapImageRep(data: tiffData) {
                        let pngData = bitmapImage.representation(using: .png, properties: [:])
                        do {
                            try pngData?.write(to: url)
                            print("✅ Image saved to: \(url.path)")
                        } catch {
                            print("❌ Failed to save image: \(error)")
                            ErrorHandler.shared.handle(error)
                        }
                    }
                }
            }
        }
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
            pasteboard.setData(tiffData, forType: .png)
            print("✅ Edited image copied to clipboard")
            
            // Show brief feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // The clipboard monitor will detect the change and add to history
            }
        }
    }
    
    func isShowing() -> Bool {
        return editorWindow != nil && editorWindow?.isVisible == true
    }
}

