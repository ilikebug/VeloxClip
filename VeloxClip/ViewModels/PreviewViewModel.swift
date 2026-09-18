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
        PasteboardSelfWriteGate.shared.write(text)
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        item.copyToPasteboard()
        ClipboardStore.shared.markUsed(item.id)
    }
}
