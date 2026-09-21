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

extension ClipboardItem {
    /// How a `file` item encodes its paths: one per line, empty lines dropped.
    /// Never trimmed — a file name may legitimately begin or end with a space.
    ///
    /// This is domain knowledge (the item's own storage format), not
    /// presentation; it used to live in RowPresentation, which made the entity
    /// depend on the presentation layer.
    static func filePaths(from content: String) -> [String] {
        content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}

