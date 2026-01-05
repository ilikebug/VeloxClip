import Foundation
import AppKit

@MainActor
class ScreenshotService {
    static let shared = ScreenshotService()
    
    private init() {}
    
    // Capture area screenshot using macOS built-in tool
    // This will trigger the system screenshot UI and copy to clipboard
    func captureArea() {
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
            // Don't wait for exit - let it run in background
            // The screenshot is automatically copied to clipboard by screencapture
            // ClipboardMonitor will detect it and add it to history
        } catch {
            print("Failed to launch screenshot tool: \(error)")
        }
    }
}

