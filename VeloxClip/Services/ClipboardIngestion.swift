import Foundation
import ImageIO

/// Pure, testable pieces of the pasteboard ingestion pipeline that
/// `ClipboardMonitor` runs on every clipboard change.
enum ClipboardIngestion {
    /// Regex-based tag scans (URL / Email / Phone) are skipped above this length —
    /// they are O(n²) worst case on pathological input and worthless on huge pastes.
    static let maxTaggableLength = 50_000

    /// Two copies of identical content inside this window collapse into one item.
    static let duplicateWindow: TimeInterval = 5.0

    /// Text shorter than this carries too little signal to embed.
    static let minEmbeddableLength = 3
    /// Upper bound on what gets an embedding at ingest time. `AIService` must be
    /// willing to embed at least this much, or items in the gap are only
    /// partially represented in semantic search.
    static let maxEmbeddableLength = 2000

    /// True when a text item is worth spending an embedding on.
    static func isEmbeddable(_ text: String) -> Bool {
        (minEmbeddableLength...maxEmbeddableLength).contains(text.count)
    }

    /// Pixel ceiling checked BEFORE any decode — a decompression bomb from the
    /// pasteboard would otherwise take the app down on the next poll tick.
    static let maxImagePixels = 100_000_000
    /// Byte ceiling for what actually goes into SQLite. Applied to the normalized
    /// PNG, never to the raw pasteboard bytes: pasteboard TIFF is uncompressed, so
    /// an ordinary 5K screenshot is ~59MB raw but only a few MB stored.
    static let maxImageBytes = 50 * 1024 * 1024

    /// Shared with `ContentDetectionService`; the monitor tags on any single hit,
    /// the detection service requires two.
    static let codeIndicators = ["func ", "class ", "def ", "import ", "const ", "let ", "var ", "function ", "=>", "->", "public ", "private "]

    private static let hexColorPattern = "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3}|[A-Fa-f0-9]{8})$"
    private static let rgbColorPattern = #"^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$"#
    private static let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    private static let phonePattern = "\\b\\d{3}[-.]?\\d{3,4}[-.]?\\d{4}\\b"

    static func isColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: hexColorPattern, options: .regularExpression) != nil ||
               trimmed.range(of: rgbColorPattern, options: .regularExpression) != nil
    }

    static func detectTags(in text: String) -> [String] {
        var tags: [String] = []

        if text.count <= maxTaggableLength {
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
               !detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).isEmpty {
                tags.append("URL")
            }
            if text.contains("@"), text.contains("."),
               text.range(of: emailPattern, options: .regularExpression) != nil {
                tags.append("Email")
            }
            if text.range(of: phonePattern, options: .regularExpression) != nil {
                tags.append("Phone")
            }
        }

        if codeIndicators.contains(where: { text.contains($0) }) {
            tags.append("Code")
        }

        if (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]")),
           (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil {
            tags.append("JSON")
        }

        return tags
    }

    /// The most recent item that is the same copy repeated inside `duplicateWindow`, if any.
    static func recentDuplicate(in items: [ClipboardItem],
                                type: String,
                                content: String?,
                                dataHash: String?,
                                now: Date) -> ClipboardItem? {
        items.prefix(10).first { recent in
            recent.type == type && recent.content == content && recent.dataHash == dataHash &&
            now.timeIntervalSince(recent.createdAt) < duplicateWindow
        }
    }

    /// Header-only pixel check (no decode) on the RAW pasteboard bytes.
    /// Data ImageIO can't even parse passes: it can't be a decompression bomb
    /// because nothing will decode it, and dropping it would silently lose a copy.
    static func imageDimensionsWithinLimit(_ data: Data, maxPixels: Int = maxImagePixels) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return true }
        return width * height <= maxPixels
    }

    /// Size check on the NORMALIZED blob — the bytes that would land in the database.
    static func imageStorable(_ data: Data, maxBytes: Int = maxImageBytes) -> Bool {
        data.count <= maxBytes
    }
}
