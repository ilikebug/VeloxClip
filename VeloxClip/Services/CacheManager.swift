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

            // View-layer caches register themselves (see Views/ViewCaches.swift)
            // so this service never has to name a SwiftUI view type
            CacheRegistry.clearAll()

            // Clear list thumbnails
            ThumbnailProvider.shared.clear()

            print("✅ All caches cleared")
        }
    }
}
