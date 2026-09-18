import Foundation
import CryptoKit

struct ClipboardItem: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var createdAt: Date
    var lastUsedAt: Date?
    var type: String
    var content: String?
    var data: Data?
    var dataHash: String?
    var sourceApp: String?

    // AI Metadata
    var tags: [String] = []
    var embedding: Data?

    // Favorite Metadata
    var isFavorite: Bool = false
    var favoritedAt: Date?

    var vector: [Double]? {
        Self.decodeVector(embedding)
    }

    /// False for an image/RTF whose blob is gone (row deleted after it was
    /// selected, or not yet lazy-loaded). Pasting such a ghost used to clear the
    /// clipboard and write nothing — or, for an OCR'd image, paste the OCR text.
    var hasPasteablePayload: Bool {
        if type == "image" || type == "rtf" { return data != nil }
        return content != nil || data != nil
    }

    func localizedTypeName(language: AppLanguage) -> String {
        switch type {
        case "text":  return L10n.string("clipboard.type.text", language: language)
        case "image": return L10n.string("clipboard.type.image", language: language)
        case "file":  return L10n.string("clipboard.type.file", language: language)
        case "color": return L10n.string("clipboard.type.color", language: language)
        case "rtf":   return L10n.string("clipboard.type.rtf", language: language)
        default:      return type.capitalized
        }
    }

    init(type: String, content: String? = nil, data: Data? = nil, sourceApp: String? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.type = type
        self.content = content
        self.data = data
        self.dataHash = data.map(Self.hash(of:))
        self.sourceApp = sourceApp
    }

    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // Embeddings are stored as raw Double bytes; legacy rows hold JSON arrays ("[...")
    static func encodeVector(_ vector: [Double]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decodeVector(_ data: Data?) -> [Double]? {
        guard let data, !data.isEmpty else { return nil }
        if data.first == UInt8(ascii: "[") {
            return try? JSONDecoder().decode([Double].self, from: data)
        }
        guard data.count % MemoryLayout<Double>.stride == 0 else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
    }

    // data/embedding can be multi-megabyte blobs; equality and hashing must not touch them
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.createdAt == rhs.createdAt &&
        lhs.lastUsedAt == rhs.lastUsedAt &&
        lhs.type == rhs.type &&
        lhs.content == rhs.content &&
        lhs.dataHash == rhs.dataHash &&
        lhs.sourceApp == rhs.sourceApp &&
        lhs.tags == rhs.tags &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.favoritedAt == rhs.favoritedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

import AppKit

extension ClipboardItem {
    @MainActor
    func copyToPasteboard(_ pasteboard: NSPasteboard = .general) {
        guard hasPasteablePayload else { return }

        // Decode before clearing: a blob NSImage can't decode must leave the
        // user's clipboard intact, not empty (which the paste stack would then
        // record as its own successful write and silently skip the item)
        var decodedImage: NSImage?
        if type == "image" {
            guard let d = data, let nsImage = NSImage(data: d) else {
                print("❌ Failed to create NSImage from data")
                return
            }
            decodedImage = nsImage
        }

        pasteboard.clearContents()
        defer { if pasteboard == NSPasteboard.general { PasteboardSelfWriteGate.shared.recordSelfWrite() } }

        if let decodedImage, let d = data {
            Self.writeImage(decodedImage, encoded: d, to: pasteboard)
            return
        }

        if type == "color", let c = content {
            pasteboard.setString(c, forType: .string)
            return
        }

        if type == "file", let c = content {
            // Write real file URLs so pasting into Finder reproduces the files;
            // fall back to the plain paths if none of them still exist
            let urls = RowPresentation.filePaths(from: c)
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty, pasteboard.writeObjects(urls) {
                return
            }
            pasteboard.setString(c, forType: .string)
            return
        }

        if let c = content {
            pasteboard.setString(c, forType: .string)
        } else if let d = data {
            if type == "rtf" {
                pasteboard.setData(d, forType: .rtf)
            }
        }
    }
}

extension ClipboardItem {
    /// Writes the NSImage object (consumers get TIFF on demand) plus the encoded
    /// bytes as an explicit representation. Stored blobs are PNG (normalized on
    /// ingest) and go out byte-for-byte — the previous path re-encoded a full
    /// TIFF twice and a PNG once per paste, on the main thread.
    @MainActor
    static func writeImage(_ image: NSImage, encoded: Data?, to pasteboard: NSPasteboard) {
        pasteboard.writeObjects([image])   // TIFF promise for every consumer
        if let encoded, encoded.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            pasteboard.setData(encoded, forType: .png)
        } else if let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            // Legacy JPEG/TIFF blobs: one PNG encode (never declare foreign bytes as TIFF)
            pasteboard.setData(png, forType: .png)
        }
    }
}

// Tracks pasteboard writes made by the app itself so ClipboardMonitor
// doesn't re-ingest them as new history items.
@MainActor
final class PasteboardSelfWriteGate {
    static let shared = PasteboardSelfWriteGate()

    private(set) var lastSelfWriteChangeCount: Int = -1

    private init() {}

    func recordSelfWrite() {
        lastSelfWriteChangeCount = NSPasteboard.general.changeCount
    }

    /// Clear + set a plain string + record the self-write, in one step. Every
    /// "copy X" button must go through here, or the monitor records the copy as
    /// a brand-new history item.
    func write(_ string: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        if pasteboard == NSPasteboard.general { recordSelfWrite() }
    }

    func isSelfWrite(changeCount: Int) -> Bool {
        changeCount == lastSelfWriteChangeCount
    }
}
