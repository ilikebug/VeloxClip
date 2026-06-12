import AppKit
import ImageIO

// Generates and caches small list thumbnails for image items.
// Blobs are lazy-loaded from the database (list items carry data == nil),
// so thumbnails are decoded on demand and kept in a bounded FIFO cache.
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var cache = FIFOCache<UUID, NSImage>(maxEntries: 200)

    private init() {}

    func cachedThumbnail(for id: UUID) -> NSImage? {
        cache[id]
    }

    func thumbnail(for id: UUID) async -> NSImage? {
        if let cached = cache[id] {
            return cached
        }

        guard let data = await ClipboardStore.shared.loadData(for: id) else { return nil }

        let image = await Task.detached(priority: .userInitiated) { @Sendable () -> NSImage? in
            Self.makeThumbnail(from: data, maxPixelSize: 96)
        }.value

        if let image {
            cache[id] = image
        }
        return image
    }

    func clear() {
        cache.removeAll()
    }

    // CGImageSource decodes straight to the target size — far cheaper than
    // loading the full image and scaling it down. Internal for unit testing.
    nonisolated static func makeThumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
