import Foundation

/// Lets cache owners hand `CacheManager` a way to clear them, instead of
/// `CacheManager` naming them.
///
/// `CacheManager` used to reach up into the view layer and mutate statics on
/// SwiftUI View types (`MarkdownView.chunksCache`, `JSONPreviewView.jsonCache`).
/// That inverted the dependency direction — Services could not compile without
/// the view tree — and split ownership: the View declared the state, a Service
/// was responsible for reclaiming it, and adding a third cached preview silently
/// broke "clear all caches" with no compiler help.
@MainActor
enum CacheRegistry {
    private static var clearHandlers: [() -> Void] = []

    /// Registers a cache. Call once, from the owner's static initialisation.
    static func register(_ clear: @escaping () -> Void) {
        clearHandlers.append(clear)
    }

    static func clearAll() {
        for clear in clearHandlers {
            clear()
        }
    }
}
