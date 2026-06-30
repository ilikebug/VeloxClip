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
    var summary: String?
    var isSensitive: Bool = false
    var embedding: Data?

    // Favorite Metadata
    var isFavorite: Bool = false
    var favoritedAt: Date?

    var vector: [Double]? {
        Self.decodeVector(embedding)
    }

    /// User-facing name for the clipboard type. Defaults to Chinese for legacy tests and callers.
    var localizedTypeName: String {
        localizedTypeName(language: .zhHans)
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
        lhs.summary == rhs.summary &&
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
    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { PasteboardSelfWriteGate.shared.recordSelfWrite() }

        if type == "image", let d = data {
            // Try to create NSImage from data
            guard let nsImage = NSImage(data: d) else {
                print("❌ Failed to create NSImage from data")
                return
            }

            // Primary method: Write NSImage object directly (most compatible)
            let writeSuccess = pasteboard.writeObjects([nsImage])
            print("✅ Image copied to pasteboard: \(writeSuccess)")

            // Backup: Also set TIFF representation for compatibility
            if let tiffData = nsImage.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }

            // Backup: Also try PNG format
            if let tiffData = nsImage.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }

            return
        }

        if type == "color", let c = content {
            pasteboard.setString(c, forType: .string)
            return
        }

        if type == "file", let c = content {
            // Write real file URLs so pasting into Finder reproduces the files;
            // fall back to the plain paths if none of them still exist
            let urls = c.components(separatedBy: .newlines)
                .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
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

    func isSelfWrite(changeCount: Int) -> Bool {
        changeCount == lastSelfWriteChangeCount
    }
}
