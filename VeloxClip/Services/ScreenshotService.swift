import Foundation
import AppKit

@MainActor
class ScreenshotService {
    static let shared = ScreenshotService()
    
    private var isWaitingForScreenshot = false
    private var previousChangeCount: Int = 0
    private var monitoringTimer: Timer?
    private var timeoutTask: Task<Void, Never>?
    
    private init() {}
    
    // Capture area screenshot using macOS built-in tool
    // This will trigger the system screenshot UI and copy to clipboard
    func captureArea() {
        // The press that raises the permission dialog must not also start a
        // capture — its mouse grab would make the dialog unclickable. Every
        // later press runs regardless of the (stale until relaunch) preflight.
        guard !ScreenCapturePermission.promptIfNeeded() else { return }

        let pasteboard = NSPasteboard.general
        previousChangeCount = pasteboard.changeCount
        
        // Use screencapture command with -i flag for interactive area selection
        // -c flag copies to clipboard
        // -x flag disables sound
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c", "-x"]
        
        // Launch the screenshot tool asynchronously
        // This will show the crosshair cursor for area selection
        do {
            try task.run()
            isWaitingForScreenshot = true
            
            // Start monitoring clipboard to detect when screenshot is complete
            startClipboardMonitoring()
            
            // Timeout tied to THIS capture — a stale one from an earlier, cancelled
            // capture must not tear down the monitoring of a later one
            timeoutTask?.cancel()
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds timeout
                guard !Task.isCancelled, isWaitingForScreenshot else { return }
                stopClipboardMonitoring()
                isWaitingForScreenshot = false
            }
        } catch {
            print("Failed to launch screenshot tool: \(error)")
        }
    }
    
    private func startClipboardMonitoring() {
        // Stop existing timer if any
        stopClipboardMonitoring()
        
        // Monitor clipboard changes to detect screenshot completion
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isWaitingForScreenshot else {
                    self?.stopClipboardMonitoring()
                    return
                }
                self.checkClipboard()
            }
        }
        
        // Add timer to RunLoop
        if let timer = monitoringTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func stopClipboardMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    private func checkClipboard() {
        guard isWaitingForScreenshot else { return }
        
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        guard currentChangeCount != previousChangeCount else { return }
        
        // Check if clipboard contains an image
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let _ = NSImage(data: imageData) {
            // Screenshot detected, open main window to show history
            stopClipboardMonitoring()
            timeoutTask?.cancel()
            isWaitingForScreenshot = false
            
            // Open main window after a short delay to ensure image is saved to history
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                WindowManager.shared.showOverlay()   // never toggle — it would hide an open overlay
            }
        }
    }
}

