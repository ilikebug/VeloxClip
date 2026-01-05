import Foundation
import AppKit

@MainActor
class ScreenshotService {
    static let shared = ScreenshotService()
    
    private var isWaitingForScreenshot = false
    private var previousChangeCount: Int = 0
    private var monitoringTimer: Timer?
    
    private init() {}
    
    // Capture area screenshot using macOS built-in tool
    // This will trigger the system screenshot UI and copy to clipboard
    func captureArea() {
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
            
            // Set a timeout to stop monitoring
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds timeout
                if isWaitingForScreenshot {
                    stopClipboardMonitoring()
                    isWaitingForScreenshot = false
                }
            }
        } catch {
            print("Failed to launch screenshot tool: \(error)")
        }
    }
    
    private func startClipboardMonitoring() {
        // Stop existing timer if any
        stopClipboardMonitoring()
        
        // Monitor clipboard changes to detect screenshot completion
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self, self.isWaitingForScreenshot else {
                timer.invalidate()
                return
            }
            
            Task { @MainActor in
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
            isWaitingForScreenshot = false
            
            // Open main window after a short delay to ensure image is saved to history
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                WindowManager.shared.toggleWindow()
            }
        }
    }
}

