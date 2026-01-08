import SwiftUI
import AppKit
import UserNotifications

@MainActor
class PreviewViewModel: ObservableObject {
    @Published var detectedType: DetectedContentType = .plain
    @Published var isAIProcessing = false
    @Published var aiError: String?
    @Published var isContentLoading = false
    
    private var detectionTask: Task<Void, Never>?
    
    func updateItem(_ item: ClipboardItem?) {
        detectionTask?.cancel()
        
        guard let item = item else {
            detectedType = .plain
            isContentLoading = false
            return
        }
        
        isContentLoading = true
        
        detectionTask = Task {
            let type = await ContentDetectionService.shared.detectType(for: item)
            if Task.isCancelled { return }
            self.detectedType = type
            self.isContentLoading = false
        }
    }
    
    func performAIAction(_ action: AIAction, content: String) async {
        isAIProcessing = true
        aiError = nil
        
        do {
            let result = try await LLMService.shared.performAction(action, content: content)
            copyTransformedText(result)
            sendNotification(for: action, success: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            ErrorHandler.shared.handle(error)
            aiError = "AI Service Failed: \(error.localizedDescription)"
            sendNotification(for: action, success: false)
        }
        isAIProcessing = false
    }
    
    private func sendNotification(for action: AIAction, success: Bool) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            
            // Check authorization status
            let settings = await center.notificationSettings()
            
            // Only send notification if authorized
            guard settings.authorizationStatus == .authorized else {
                print("⚠️ Cannot send notification: authorization status is \(settings.authorizationStatus.rawValue)")
                // Don't request permission here - it should be requested at app launch
                return
            }
            
            // Create notification content
            let content = UNMutableNotificationContent()
            if success {
                content.title = "AI Action Completed"
                content.body = "\(action.rawValue) completed. Result copied to clipboard."
                content.sound = .default
            } else {
                content.title = "AI Action Failed"
                content.body = "Failed to perform \(action.rawValue). Please check your settings."
                content.sound = .default
            }
            
            // Create notification request with immediate trigger
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // nil means immediate delivery
            )
            
            // Add notification request
            do {
                try await center.add(request)
                print("✅ Notification sent successfully")
            } catch {
                print("❌ Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    func copyTransformedText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        item.copyToPasteboard()
    }
}
