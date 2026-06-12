import Foundation
import SQLite

actor DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: Connection?
    private let dbPath: URL
    private var isInitialized = false
    private let fileManager: FileManager
    private let legacyDatabaseURLs: [URL]
    
    // Clipboard items table
    let clipboardItems = Table("clipboard_items")
    let id = Expression<String>("id")
    let createdAt = Expression<Double>("createdAt")
    let lastUsedAt = Expression<Double?>("lastUsedAt")
    let type = Expression<String>("type")
    let content = Expression<String?>("content")
    let data = Expression<Data?>("data")
    let dataHash = Expression<String?>("dataHash")
    let sourceApp = Expression<String?>("sourceApp")
    let tags = Expression<String>("tags")
    let summary = Expression<String?>("summary")
    let isSensitive = Expression<Bool>("isSensitive")
    let embedding = Expression<Data?>("embedding")
    let isFavorite = Expression<Bool>("isFavorite")
    let favoritedAt = Expression<Double?>("favoritedAt")
    
    // App settings table
    let appSettings = Table("app_settings")
    let key = Expression<String>("key")
    let value = Expression<String>("value")
    
    init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        
        // Target paths
        let targetURL = appSupportURL.appendingPathComponent("VeloxClip")
        let targetDBPath = targetURL.appendingPathComponent("veloxclip.db")
        let legacyDatabaseURLs = [
            appSupportURL.appendingPathComponent("Velox").appendingPathComponent("velox.db"),
            appSupportURL.appendingPathComponent("Velo").appendingPathComponent("velo.db"),
        ]

        dbPath = targetDBPath
        self.fileManager = fileManager
        self.legacyDatabaseURLs = legacyDatabaseURLs
        Self.prepareDatabaseLocation(
            dbPath: targetDBPath,
            legacyDatabaseURLs: legacyDatabaseURLs,
            fileManager: fileManager
        )
    }

    init(databaseURL: URL, legacyDatabaseURLs: [URL] = [], fileManager: FileManager = .default) {
        self.dbPath = databaseURL
        self.fileManager = fileManager
        self.legacyDatabaseURLs = legacyDatabaseURLs
        Self.prepareDatabaseLocation(
            dbPath: databaseURL,
            legacyDatabaseURLs: legacyDatabaseURLs,
            fileManager: fileManager
        )
    }

    private static func prepareDatabaseLocation(dbPath: URL, legacyDatabaseURLs: [URL], fileManager: FileManager) {
        let targetDirectory = dbPath.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: dbPath.path) {
            for legacyDB in legacyDatabaseURLs where fileManager.fileExists(atPath: legacyDB.path) {
                do {
                    try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
                    try fileManager.moveItem(at: legacyDB, to: dbPath)
                    print("✅ Migrated database from \(legacyDB.lastPathComponent) to \(dbPath.path)")
                    try? fileManager.removeItem(at: legacyDB.deletingLastPathComponent())
                    break
                } catch {
                    print("⚠️ Migration failed from \(legacyDB.path): \(error)")
                }
            }
        }

        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try? fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }
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
                t.column(lastUsedAt)
                t.column(self.type)
                t.column(content)
                t.column(data)
                t.column(dataHash)
                t.column(sourceApp)
                t.column(tags, defaultValue: "[]")
                t.column(summary)
                t.column(isSensitive, defaultValue: false)
                t.column(embedding)
                t.column(isFavorite, defaultValue: false)
                t.column(favoritedAt)
            })
            
            // Create app_settings table
            try db.run(appSettings.create(ifNotExists: true) { t in
                t.column(key, primaryKey: true)
                t.column(self.value)
            })

            try migrateClipboardItemsTableIfNeeded()
            
            // Optimization: Add indexes for frequently queried/sorted columns
            try db.run(clipboardItems.createIndex(createdAt, ifNotExists: true))
            try db.run(clipboardItems.createIndex(isFavorite, ifNotExists: true))
            
        } catch {
            print("Failed to create tables or indexes: \(error)")
            Task { @MainActor in
                ErrorHandler.shared.handle(error)
            }
        }
    }

    private func migrateClipboardItemsTableIfNeeded() throws {
        guard let db = db else { return }

        let existingColumns = Set(try db.prepare("PRAGMA table_info(clipboard_items)").compactMap { row in
            row[1] as? String
        })

        let requiredColumns: [(name: String, definition: String)] = [
            ("tags", #"TEXT NOT NULL DEFAULT '[]'"#),
            ("summary", "TEXT"),
            ("isSensitive", "BOOLEAN NOT NULL DEFAULT 0"),
            ("embedding", "BLOB"),
            ("isFavorite", "BOOLEAN NOT NULL DEFAULT 0"),
            ("favoritedAt", "DOUBLE"),
            ("lastUsedAt", "DOUBLE"),
            ("dataHash", "TEXT"),
        ]

        for column in requiredColumns where !existingColumns.contains(column.name) {
            try db.run("ALTER TABLE clipboard_items ADD COLUMN \(column.name) \(column.definition)")
        }

        try backfillDataHashesIfNeeded()
    }

    // One-time backfill so hash-based dedup also covers rows created before the dataHash column existed.
    // Guarded by a settings flag — new rows always get a hash on insert, so once this has run
    // there is nothing left to scan on subsequent launches.
    private func backfillDataHashesIfNeeded() throws {
        guard let db = db else { return }

        let backfillFlag = "dataHashBackfillDone"
        if try db.pluck(appSettings.filter(key == backfillFlag)) != nil { return }

        let pending = clipboardItems.select(id, data).filter(dataHash == nil && data != nil)
        for row in try db.prepare(pending) {
            guard let blob = row[data] else { continue }
            let hash = ClipboardItem.hash(of: blob)
            try db.run(clipboardItems.filter(id == row[id]).update(dataHash <- hash))
        }

        try db.run(appSettings.insert(or: .replace, key <- backfillFlag, value <- "1"))
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
            lastUsedAt <- item.lastUsedAt?.timeIntervalSince1970,
            type <- item.type,
            content <- item.content,
            data <- item.data,
            dataHash <- item.dataHash,
            sourceApp <- item.sourceApp,
            tags <- tagsString,
            summary <- item.summary,
            isSensitive <- item.isSensitive,
            embedding <- item.embedding,
            isFavorite <- item.isFavorite,
            favoritedAt <- item.favoritedAt?.timeIntervalSince1970
        )

        try db.run(insert)
    }

    func updateClipboardItem(_ item: ClipboardItem) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        let tagsJSON = try JSONEncoder().encode(item.tags)
        let tagsString = String(data: tagsJSON, encoding: .utf8) ?? "[]"

        let itemRow = clipboardItems.filter(id == item.id.uuidString)

        var setters: [Setter] = [
            content <- item.content,
            lastUsedAt <- item.lastUsedAt?.timeIntervalSince1970,
            sourceApp <- item.sourceApp,
            tags <- tagsString,
            summary <- item.summary,
            isSensitive <- item.isSensitive,
            embedding <- item.embedding,
            isFavorite <- item.isFavorite,
            favoritedAt <- item.favoritedAt?.timeIntervalSince1970
        ]
        // Items fetched for the list view carry data == nil (lazy-loaded);
        // never overwrite the stored blob with nil in that case
        if item.data != nil {
            setters.append(data <- item.data)
            setters.append(dataHash <- item.dataHash)
        }

        try db.run(itemRow.update(setters))
    }
    
    // Lightweight "used just now" update — touches a single column instead of
    // rewriting the whole row (content, embedding, …) on every paste
    func touchItem(id itemID: UUID, lastUsedAt date: Date) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        let itemRow = clipboardItems.filter(id == itemID.uuidString)
        try db.run(itemRow.update(lastUsedAt <- date.timeIntervalSince1970))
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
    
    // List queries skip the `data` blob column — images can be megabytes each
    // and the list only needs metadata. Use fetchItemData(id:) to load blobs on demand.
    private var listColumns: [Expressible] {
        [id, createdAt, lastUsedAt, type, content, dataHash, sourceApp, tags, summary, isSensitive, embedding, isFavorite, favoritedAt]
    }

    private var sortKey: SQLite.Expression<Double> {
        lastUsedAt ?? createdAt
    }

    func fetchAllClipboardItems() async throws -> [ClipboardItem] {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        var items: [ClipboardItem] = []

        for row in try db.prepare(clipboardItems.select(listColumns).order(sortKey.desc)) {
            let item = try rowToClipboardItem(row, includesData: false)
            items.append(item)
        }

        return items
    }

    func fetchClipboardItems(limit: Int) async throws -> [ClipboardItem] {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        var items: [ClipboardItem] = []

        for row in try db.prepare(clipboardItems.select(listColumns).order(sortKey.desc).limit(limit)) {
            let item = try rowToClipboardItem(row, includesData: false)
            items.append(item)
        }

        return items
    }

    func fetchItemData(id itemID: UUID) async throws -> Data? {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = clipboardItems.select(data).filter(id == itemID.uuidString)
        guard let row = try db.pluck(query) else { return nil }
        return row[data]
    }

    private func rowToClipboardItem(_ row: Row, includesData: Bool = true) throws -> ClipboardItem {
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
            data: includesData ? row[data] : nil,
            sourceApp: row[sourceApp]
        )

        item.id = itemID
        item.createdAt = createdAtDate
        item.dataHash = row[dataHash]
        if let lastUsedAtTimestamp = row[lastUsedAt] {
            item.lastUsedAt = Date(timeIntervalSince1970: lastUsedAtTimestamp)
        }
        item.tags = tagsArray
        item.summary = row[summary]
        item.isSensitive = row[isSensitive]
        item.embedding = row[embedding]
        item.isFavorite = row[isFavorite]
        if let favoritedAtTimestamp = row[favoritedAt] {
            item.favoritedAt = Date(timeIntervalSince1970: favoritedAtTimestamp)
        }
        
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
    
    func settingExists(key: String) async -> Bool {
        await ensureInitialized()
        guard let db = db else { return false }
        
        do {
            let query = appSettings.filter(self.key == key)
            return try db.pluck(query) != nil
        } catch {
            print("Failed to check if setting \(key) exists: \(error)")
            return false
        }
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
    
    // MARK: - Favorite Operations
    
    func toggleFavorite(id: UUID) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let itemRow = clipboardItems.filter(self.id == id.uuidString)
        if let row = try db.pluck(itemRow) {
            let currentFavorite = row[isFavorite]
            let newFavorite = !currentFavorite
            let newFavoritedAt = newFavorite ? Date().timeIntervalSince1970 : nil
            
            try db.run(itemRow.update(
                isFavorite <- newFavorite,
                favoritedAt <- newFavoritedAt
            ))
        }
    }
    
    func fetchFavoriteItems() async throws -> [ClipboardItem] {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var items: [ClipboardItem] = []
        
        for row in try db.prepare(clipboardItems.select(listColumns).filter(isFavorite == true).order(favoritedAt.desc)) {
            let item = try rowToClipboardItem(row, includesData: false)
            items.append(item)
        }
        
        return items
    }
}

enum DatabaseError: Error {
    case connectionFailed
    case invalidData
    case operationFailed(String)
}
