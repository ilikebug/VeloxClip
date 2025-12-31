import Foundation
import SQLite

actor DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: Connection?
    private let dbPath: URL
    private var isInitialized = false
    
    // Clipboard items table
    let clipboardItems = Table("clipboard_items")
    let id = Expression<String>("id")
    let createdAt = Expression<Double>("createdAt")
    let type = Expression<String>("type")
    let content = Expression<String?>("content")
    let data = Expression<Data?>("data")
    let sourceApp = Expression<String?>("sourceApp")
    let tags = Expression<String>("tags")
    let summary = Expression<String?>("summary")
    let isSensitive = Expression<Bool>("isSensitive")
    let embedding = Expression<Data?>("embedding")
    
    // App settings table
    let appSettings = Table("app_settings")
    let key = Expression<String>("key")
    let value = Expression<String>("value")
    
    init() {
        // Get Application Support directory
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let veloxURL = appSupportURL.appendingPathComponent("Velox")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: veloxURL, withIntermediateDirectories: true, attributes: nil)
        
        // Database file path
        dbPath = veloxURL.appendingPathComponent("velox.db")
    }
    
    // Initialize database on first access (lazy initialization)
    private func ensureInitialized() async {
        guard !isInitialized else { return }
        
        do {
            db = try Connection(dbPath.path)
            createTables()
            isInitialized = true
        } catch {
            print("Failed to initialize database: \(error)")
            Task { @MainActor in
                ErrorHandler.shared.handle(error)
            }
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        
        do {
            // Create clipboard_items table
            try db.run(clipboardItems.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(createdAt)
                t.column(self.type)
                t.column(content)
                t.column(data)
                t.column(sourceApp)
                t.column(tags, defaultValue: "[]")
                t.column(summary)
                t.column(isSensitive, defaultValue: false)
                t.column(embedding)
            })
            
            // Create app_settings table
            try db.run(appSettings.create(ifNotExists: true) { t in
                t.column(key, primaryKey: true)
                t.column(self.value)
            })
        } catch {
            print("Failed to create tables: \(error)")
            Task { @MainActor in
                ErrorHandler.shared.handle(error)
            }
        }
    }
    
    // MARK: - Clipboard Items Operations
    
    func insertClipboardItem(_ item: ClipboardItem) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        // Check if item already exists
        let existingItem = clipboardItems.filter(id == item.id.uuidString)
        if try db.pluck(existingItem) != nil {
            // Item already exists, skip insertion
            return
        }
        
        let tagsJSON = try JSONEncoder().encode(item.tags)
        let tagsString = String(data: tagsJSON, encoding: .utf8) ?? "[]"
        
        let insert = clipboardItems.insert(
            id <- item.id.uuidString,
            createdAt <- item.createdAt.timeIntervalSince1970,
            type <- item.type,
            content <- item.content,
            data <- item.data,
            sourceApp <- item.sourceApp,
            tags <- tagsString,
            summary <- item.summary,
            isSensitive <- item.isSensitive,
            embedding <- item.embedding
        )
        
        try db.run(insert)
    }
    
    func updateClipboardItem(_ item: ClipboardItem) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let tagsJSON = try JSONEncoder().encode(item.tags)
        let tagsString = String(data: tagsJSON, encoding: .utf8) ?? "[]"
        
        let itemRow = clipboardItems.filter(id == item.id.uuidString)
        
        try db.run(itemRow.update(
            content <- item.content,
            data <- item.data,
            sourceApp <- item.sourceApp,
            tags <- tagsString,
            summary <- item.summary,
            isSensitive <- item.isSensitive,
            embedding <- item.embedding
        ))
    }
    
    func deleteClipboardItem(id: UUID) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let itemRow = clipboardItems.filter(self.id == id.uuidString)
        try db.run(itemRow.delete())
    }
    
    func deleteAllClipboardItems() async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        try db.run(clipboardItems.delete())
    }
    
    func fetchAllClipboardItems() async throws -> [ClipboardItem] {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var items: [ClipboardItem] = []
        
        for row in try db.prepare(clipboardItems.order(createdAt.desc)) {
            let item = try rowToClipboardItem(row)
            items.append(item)
        }
        
        return items
    }
    
    func fetchClipboardItems(limit: Int) async throws -> [ClipboardItem] {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var items: [ClipboardItem] = []
        
        for row in try db.prepare(clipboardItems.order(createdAt.desc).limit(limit)) {
            let item = try rowToClipboardItem(row)
            items.append(item)
        }
        
        return items
    }
    
    private func rowToClipboardItem(_ row: Row) throws -> ClipboardItem {
        guard let itemID = UUID(uuidString: row[id]) else {
            throw DatabaseError.invalidData
        }
        
        let createdAtDate = Date(timeIntervalSince1970: row[createdAt])
        let tagsString = row[tags]
        let tagsArray: [String]
        
        if let tagsData = tagsString.data(using: .utf8) {
            tagsArray = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
        } else {
            tagsArray = []
        }
        
        var item = ClipboardItem(
            type: row[type],
            content: row[content],
            data: row[data],
            sourceApp: row[sourceApp]
        )
        
        item.id = itemID
        item.createdAt = createdAtDate
        item.tags = tagsArray
        item.summary = row[summary]
        item.isSensitive = row[isSensitive]
        item.embedding = row[embedding]
        
        return item
    }
    
    // MARK: - App Settings Operations
    
    func getSetting(key: String) async -> String? {
        await ensureInitialized()
        guard let db = db else { return nil }
        
        do {
            let query = appSettings.filter(self.key == key)
            if let row = try db.pluck(query) {
                return row[value]
            }
        } catch {
            print("Failed to get setting \(key): \(error)")
        }
        
        return nil
    }
    
    func setSetting(key: String, value: String) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let insert = appSettings.insert(or: .replace,
            self.key <- key,
            self.value <- value
        )
        
        try db.run(insert)
    }
    
    func deleteSetting(key: String) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let settingRow = appSettings.filter(self.key == key)
        try db.run(settingRow.delete())
    }
}

enum DatabaseError: Error {
    case connectionFailed
    case invalidData
    case operationFailed(String)
}

