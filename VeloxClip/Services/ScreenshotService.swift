import Foundation
import AppKit

@MainActor
class ScreenshotService {
    static let shared = ScreenshotService()
    
    private var isWaitingForScreenshot = false
    private var previousChangeCount: Int = 0
    private var monitoringTimer: Timer?
    // The running screencapture; its exit — not a timeout — ends the wait
    private var captureProcess: Process?
    
    private init() {}
    
    // Capture area screenshot using macOS built-in tool
    // This will trigger the system screenshot UI and copy to clipboard
    func captureArea() {
        // One interactive selection at a time: a second process replaced
        // captureProcess, and its exit ended the first selection's wait
        guard captureProcess?.isRunning != true else { return }
        // The press that raises the permission dialog must not also start a
        // capture — its mouse grab would make the dialog unclickable. Every
        // later press runs regardless of the (stale until relaunch) preflight.
        guard !ScreenCapturePermission.promptIfNeeded() else { return }

        previousChangeCount = PasteboardService.shared.changeCount
        
        // Use screencapture command with -i flag for interactive area selection
        // -c flag copies to clipboard
        // -x flag disables sound
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c", "-x"]
        // Esc cancels the selection and screencapture exits without touching
        // the clipboard. Waiting on a 15 s timeout instead meant any image
        // copied in that window was taken for the screenshot.
        task.terminationHandler = { process in
            let id = ObjectIdentifier(process)
            let status = process.terminationStatus
            Task { @MainActor in
                ScreenshotService.shared.captureDidFinish(id, status: status)
            }
        }
        
        // Launch the screenshot tool asynchronously
        // This will show the crosshair cursor for area selection
        do {
            try task.run()
            captureProcess = task
            isWaitingForScreenshot = true
            
            // Start monitoring clipboard to detect when screenshot is complete
            startClipboardMonitoring()
        } catch {
            print("Failed to launch screenshot tool: \(error)")
            // The user pressed F1 and nothing happened — surface it
            ErrorHandler.shared.handle(error)
        }
    }
    
    private func captureDidFinish(_ id: ObjectIdentifier, status: Int32) {
        // A later capture owns the wait now
        guard let process = captureProcess, ObjectIdentifier(process) == id else { return }
        captureProcess = nil
        // -c writes the clipboard before exiting: one last look catches a
        // capture the poll has not seen yet; a cancelled one finds nothing new
        if status == 0 {
            checkClipboard()
        }
        stopClipboardMonitoring()
        isWaitingForScreenshot = false
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
        
        let currentChangeCount = PasteboardService.shared.changeCount

        guard currentChangeCount != previousChangeCount else { return }

        // Check if clipboard contains an image (PNG preferred over uncompressed TIFF)
        if let imageData = PasteboardService.shared.readImageData(),
           let _ = NSImage(data: imageData) {
            // Screenshot detected, open main window to show history
            stopClipboardMonitoring()
            isWaitingForScreenshot = false
            
            // Open main window after a short delay to ensure image is saved to history
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                WindowManager.shared.showOverlay()   // never toggle — it would hide an open overlay
            }
        }
    }
}

