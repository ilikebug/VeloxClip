import SwiftUI
import AppKit

@MainActor
class PreviewViewModel: ObservableObject {
    @Published var detectedType: DetectedContentType = .plain
    @Published var isContentLoading = false
    
    private var detectionTask: Task<Void, Never>?
    private let pasteboard: PasteboardService
    private let store: ClipboardStore

    init(pasteboard: PasteboardService = .shared, store: ClipboardStore = .shared) {
        self.pasteboard = pasteboard
        self.store = store
    }
    
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
        pasteboard.write(text: text)
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        // A failed write (undecodable image) must not count as a use
        guard pasteboard.write(item: item) else { return }
        store.markUsed(item.id)
    }
}
