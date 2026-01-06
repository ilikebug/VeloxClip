import SwiftUI
import AppKit

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
            try? await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            ErrorHandler.shared.handle(error)
            aiError = "AI Service Failed: \(error.localizedDescription)"
        }
        isAIProcessing = false
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
