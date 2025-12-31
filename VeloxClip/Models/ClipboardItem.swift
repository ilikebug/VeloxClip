import Foundation

struct ClipboardItem: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var createdAt: Date
    var type: String
    var content: String?
    var data: Data?
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
        guard let data = embedding else { return nil }
        return try? JSONDecoder().decode([Double].self, from: data)
    }
    
    init(type: String, content: String? = nil, data: Data? = nil, sourceApp: String? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.type = type
        self.content = content
        self.data = data
        self.sourceApp = sourceApp
    }
}
