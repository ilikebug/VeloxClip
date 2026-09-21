import Foundation

/// Registers the view layer's static caches with `CacheRegistry`.
///
/// Called once at launch. This file is the ONLY place that knows both the
/// concrete view caches and the registry — `CacheManager` used to name
/// `MarkdownView` and `JSONPreviewView` directly, which meant Services could not
/// compile without the SwiftUI view tree.
///
/// Adding a new cached preview? Register it here.
@MainActor
enum ViewCaches {
    static func registerAll() {
        CacheRegistry.register { MarkdownView.chunksCache.removeAll() }
        CacheRegistry.register { JSONPreviewView.jsonCache.removeAll() }
    }
}
