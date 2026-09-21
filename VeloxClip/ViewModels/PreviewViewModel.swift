import SwiftUI
import AppKit

@MainActor
class PreviewViewModel: ObservableObject {
    @Published var detectedType: DetectedContentType = .plain
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
    
    func copyTransformedText(_ text: String) {
        PasteboardService.shared.write(text: text)
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        PasteboardService.shared.write(item: item)
        ClipboardStore.shared.markUsed(item.id)
    }
}
