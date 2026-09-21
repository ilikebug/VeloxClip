import Foundation
import AppKit

/// What a single pasteboard change carries, extracted on the main actor before
/// any decoding happens.
struct PasteboardPayload: Sendable {
    var filePaths: String?
    var text: String?
    var rtf: Data?
    var image: Data?
    var sourceApp: String?
}

/// The classification a payload resolves to, kept pure so the type-priority
/// ladder can be tested without a pasteboard.
enum IngestKind: Equatable, Sendable {
    case file(paths: String)
    case color(String)
    case text(String)
    case rtf(Data)
    case image(Data)
    case none
}

/// Serialises clipboard ingestion.
///
/// The monitor used to spawn an independent `Task.detached` per 0.5s tick. Those
/// tasks are unordered and their durations differ by orders of magnitude — the
/// image branch does a full TIFF decode plus PNG re-encode that on a 5K
/// screenshot outlives the poll interval, while the text branch returns almost
/// immediately. Copying an image and then text within one interval therefore
/// landed the text above the image. For a clipboard manager, history order is
/// the product.
///
/// Being an actor makes `submit` FIFO: each payload is fully processed, in
/// order, before the next one starts.
actor IngestionPipeline {
    /// Injectable so tests can observe ordering without a real store.
    private let insert: @Sendable (IngestKind, String?) async -> Void

    init(insert: @escaping @Sendable (IngestKind, String?) async -> Void) {
        self.insert = insert
    }

    /// Resolves a payload to exactly one kind.
    ///
    /// Files are checked FIRST because Finder also puts the file name on the
    /// pasteboard as plain text; checking text first shadowed every file copy
    /// and recorded it as a text item.
    static func classify(_ payload: PasteboardPayload) -> IngestKind {
        if let paths = payload.filePaths, !paths.isEmpty {
            return .file(paths: paths)
        }
        if let text = payload.text {
            return ClipboardIngestion.isColor(text) ? .color(text) : .text(text)
        }
        if let rtf = payload.rtf {
            return .rtf(rtf)
        }
        if let image = payload.image {
            return .image(image)
        }
        return .none
    }

    /// Normalizes an image blob and applies both safety ceilings.
    /// Returns nil when the image must be dropped.
    static func prepareImage(_ raw: Data) -> Data? {
        // Header-only pixel check BEFORE any decode — a decompression bomb
        // on the pasteboard must not take the app down on a poll tick
        guard ClipboardIngestion.imageDimensionsWithinLimit(raw) else {
            return nil
        }
        // TIFF from the pasteboard is uncompressed (tens of MB per screenshot);
        // normalize to PNG before storing
        let normalized = normalizedImageData(raw) ?? raw
        // Size check on what would actually be stored, not on the raw TIFF
        guard ClipboardIngestion.imageStorable(normalized) else {
            return nil
        }
        return normalized
    }

    static func normalizedImageData(_ raw: Data) -> Data? {
        // Already PNG? Keep as-is
        if raw.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return raw }
        guard let rep = NSBitmapImageRep(data: raw) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Processes one payload to completion before the next begins.
    func submit(_ payload: PasteboardPayload) async {
        let kind = Self.classify(payload)

        switch kind {
        case .image(let raw):
            guard let prepared = Self.prepareImage(raw) else {
                // A copy the user made just vanished — say so rather than
                // leaving them to wonder why it never reached history.
                print("⚠️ Skipping pasteboard image: implausible dimensions or oversized after normalization")
                await MainActor.run {
                    ErrorHandler.shared.handle(IngestionError.imageRejected)
                }
                return
            }
            await insert(.image(prepared), payload.sourceApp)
        case .none:
            return
        default:
            await insert(kind, payload.sourceApp)
        }
    }
}

enum IngestionError: LocalizedError {
    case imageRejected

    var errorDescription: String? {
        "That image was too large to save to clipboard history."
    }
}
