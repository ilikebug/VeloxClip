import Foundation
import AppKit
import SwiftUI

// Window delegate to prevent app termination when window closes
class PasteImageWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Always allow window to close without terminating app
        return true
    }
}

@MainActor
class PasteImageService {
    static let shared = PasteImageService()
    
    private var pasteImageWindows: Set<NSWindow> = []
    private var eventMonitor: Any?
    private let windowDelegate = PasteImageWindowDelegate()
    
    private init() {}
    
    // Show floating image window with clipboard image
    func showPasteImage() {
        // Get image from clipboard
        let pasteboard = NSPasteboard.general
        guard let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
              let nsImage = NSImage(data: imageData) else {
            // No image in clipboard
            return
        }
        
        // Create floating window
        let window = createPasteImageWindow(image: nsImage)
        
        // Store window reference
        pasteImageWindows.insert(window)
        
        // Setup window close handler
        let closeHandler: () -> Void = { [weak self, weak window] in
            guard let self = self, let window = window else { return }
            self.closePasteImageWindow(window)
        }
        
        let contentView = PasteImageView(image: nsImage, window: window, onClose: closeHandler)
        
        let hostingController = NSHostingController(rootView: contentView)
        window.contentView = hostingController.view
        
        // Make window appear with fade-in animation
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1.0
        }
        
        // Setup ESC key monitor if not already set
        setupEventMonitorIfNeeded()
    }
    
    private func createPasteImageWindow(image: NSImage) -> NSWindow {
        // Calculate window size based on image size
        let imageSize = image.size
        let maxWidth: CGFloat = 800
        let maxHeight: CGFloat = 600
        let scale = min(1.0, min(maxWidth / imageSize.width, maxHeight / imageSize.height))
        let controlPanelHeight: CGFloat = 50 // Height for control panel at top
        let padding: CGFloat = 16 // Padding around image
        let windowSize = NSSize(
            width: imageSize.width * scale + padding * 2,
            height: imageSize.height * scale + controlPanelHeight + padding * 2
        )
        
        // Calculate position with offset to avoid overlapping windows
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let offset: CGFloat = CGFloat(pasteImageWindows.count) * 30 // Offset each new window
        let windowFrame = NSRect(
            x: screenFrame.midX - windowSize.width / 2 + offset,
            y: screenFrame.midY - windowSize.height / 2 - offset,
            width: windowSize.width,
            height: windowSize.height
        )
        
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating // Above normal windows but below system overlays
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false // Don't hide when app loses focus
        window.isReleasedWhenClosed = false // Don't release window when closed
        window.delegate = windowDelegate // Set delegate to handle window closing
        
        return window
    }
    
    private func setupEventMonitorIfNeeded() {
        // Only setup one global ESC key monitor
        guard eventMonitor == nil else { return }
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // ESC key
                // Close the topmost window
                if let topWindow = self.pasteImageWindows.first(where: { $0.isKeyWindow || $0.isMainWindow }) ?? self.pasteImageWindows.first {
                    self.closePasteImageWindow(topWindow)
                }
                return nil
            }
            return event
        }
    }
    
    private func closePasteImageWindow(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                window.orderOut(nil)
                window.close()
                self.pasteImageWindows.remove(window)
                
                // Remove event monitor if no windows left
                if self.pasteImageWindows.isEmpty {
                    if let monitor = self.eventMonitor {
                        NSEvent.removeMonitor(monitor)
                        self.eventMonitor = nil
                    }
                }
            }
        }
    }
    
    func closeAllPasteImages() {
        let windowsToClose = Array(pasteImageWindows)
        for window in windowsToClose {
            closePasteImageWindow(window)
        }
    }
    
    func isShowing() -> Bool {
        return !pasteImageWindows.isEmpty && pasteImageWindows.contains(where: { $0.isVisible })
    }
    
    func setWindowOpacity(_ opacity: Double, for window: NSWindow) {
        window.alphaValue = opacity
    }
}

// SwiftUI view for paste image window
struct PasteImageView: View {
    let image: NSImage
    let window: NSWindow
    let onClose: () -> Void
    
    @State private var opacity: Double = 0.9
    
    var body: some View {
        VStack(spacing: 0) {
            // Control panel at top
            HStack {
                Spacer()
                
                // Control buttons
                HStack(spacing: 12) {
                    // Opacity slider
                    HStack(spacing: 6) {
                        Slider(value: $opacity, in: 0.3...1.0)
                            .frame(width: 100)
                            .onChange(of: opacity) { _, newValue in
                                // Update window opacity
                                PasteImageService.shared.setWindowOpacity(newValue, for: window)
                            }
                        
                        Text("\(Int(opacity * 100))%")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(width: 35)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    
                    // Close button
                    Button(action: {
                        onClose()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Close (ESC)")
                    .padding(.trailing, 4)
                }
                .padding(8)
            }
            .background(Color.clear)
            
            // Image display
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            // Set initial opacity
            PasteImageService.shared.setWindowOpacity(opacity, for: window)
        }
    }
}

