import Foundation

@MainActor
class CacheManager {
    static let shared = CacheManager()
    
    private init() {}
    
    func clearAllCaches() {
        Task {
            // Clear AIService embedding cache
            await AIService.shared.clearEmbeddingCache()
            
            // Clear ContentDetectionService cache
            await ContentDetectionService.shared.clearCache()
            
            // Clear MarkdownView static cache
            MarkdownView.chunksCache.removeAll()
            
            // Clear JSONPreviewView static cache
            JSONPreviewView.jsonCache.removeAll()

            // Clear list thumbnails
            ThumbnailProvider.shared.clear()

            print("✅ All caches cleared")
        }
    }
}
