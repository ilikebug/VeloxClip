import Foundation
import SQLite

actor DatabaseManager {
    static let shared = DatabaseManager()

    private var db: Connection?
    private let dbPath: URL
    private var isInitialized = false
    // A persistent open/migration failure is retried on every call (cheap, and
    // it self-heals once the cause goes away) but reported once, not per call
    private var reportedInitializationFailure = false
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
    let embedding = Expression<Data?>("embedding")
    let isFavorite = Expression<Bool>("isFavorite")
    let favoritedAt = Expression<Double?>("favoritedAt")

    // App settings table
    let appSettings = Table("app_settings")
    let key = Expression<String>("key")
    let value = Expression<String>("value")

    init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

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
                    // A WAL-mode database keeps un-checkpointed rows in its sidecars;
                    // leaving them behind would silently drop the newest history
                    for suffix in ["-wal", "-shm"] {
                        let sidecar = URL(fileURLWithPath: legacyDB.path + suffix)
                        if fileManager.fileExists(atPath: sidecar.path) {
                            try fileManager.moveItem(at: sidecar, to: URL(fileURLWithPath: dbPath.path + suffix))
                        }
                    }
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

    // Initialize database on first access (lazy initialization). A failed open or
    // migration leaves `isInitialized` false so the next call retries instead of
    // running the whole session against a half-migrated schema.
    private func ensureInitialized() async {
        guard !isInitialized else { return }

        do {
            let connection = try Connection(dbPath.path)
            connection.busyTimeout = 1
            // WAL: one fsync per transaction instead of two, and readers never block the writer
            try connection.run("PRAGMA journal_mode=WAL")
            db = connection
            try createTables()
            isInitialized = true
            reportedInitializationFailure = false
        } catch {
            db = nil
            print("Failed to initialize database: \(error)")
            guard !reportedInitializationFailure else { return }
            reportedInitializationFailure = true
            Task { @MainActor in
                ErrorHandler.shared.handle(error)
            }
        }
    }

    private func createTables() throws {
        guard let db = db else { return }

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
    }

    private func migrateClipboardItemsTableIfNeeded() throws {
        guard let db = db else { return }

        let existingColumns = Set(try db.prepare("PRAGMA table_info(clipboard_items)").compactMap { row in
            row[1] as? String
        })

        let requiredColumns: [(name: String, definition: String)] = [
            ("tags", #"TEXT NOT NULL DEFAULT '[]'"#),
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

    private func encodeTags(_ tags: [String]) throws -> String {
        String(data: try JSONEncoder().encode(tags), encoding: .utf8) ?? "[]"
    }

    // MARK: - Clipboard Items Operations

    /// Inserts the item; a second insert of the same id is a no-op (`id` is the primary key).
    func insertClipboardItem(_ item: ClipboardItem) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        let insert = clipboardItems.insert(
            or: .ignore,
            id <- item.id.uuidString,
            createdAt <- item.createdAt.timeIntervalSince1970,
            lastUsedAt <- item.lastUsedAt?.timeIntervalSince1970,
            type <- item.type,
            content <- item.content,
            data <- item.data,
            dataHash <- item.dataHash,
            sourceApp <- item.sourceApp,
            tags <- try encodeTags(item.tags),
            embedding <- item.embedding,
            isFavorite <- item.isFavorite,
            favoritedAt <- item.favoritedAt?.timeIntervalSince1970
        )

        try db.run(insert)
    }

    // There is deliberately no full-row "update item from snapshot": the narrow
    // setters below can't clobber a favorite toggle or tag edit that landed while
    // a caller's in-memory snapshot was in flight, and none of them touch `data`.

    func updateTags(id itemID: UUID, tags newTags: [String]) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        try db.run(clipboardItems.filter(id == itemID.uuidString).update(tags <- try encodeTags(newTags)))
    }

    /// Background analysis result: the merged tag list plus (optionally) a new embedding.
    func updateDetectedMetadata(id itemID: UUID, tags newTags: [String], embedding vector: Data?) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        var setters: [Setter] = [tags <- try encodeTags(newTags)]
        if let vector { setters.append(embedding <- vector) }
        try db.run(clipboardItems.filter(id == itemID.uuidString).update(setters))
    }

    /// OCR result for an image: recognised text plus the tag list with "OCR" added.
    func updateContent(id itemID: UUID, content text: String, tags newTags: [String]) async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        try db.run(clipboardItems.filter(id == itemID.uuidString).update(
            content <- text,
            tags <- try encodeTags(newTags)
        ))
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
        try await deleteClipboardItems(ids: [id])
    }

    /// One statement per chunk — history trimming used to issue one fsync'd
    /// DELETE per row. Chunked to stay under SQLite's bound-variable limit.
    func deleteClipboardItems(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        let chunkSize = 500
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = ids[start..<min(start + chunkSize, ids.count)].map(\.uuidString)
            try db.run(clipboardItems.filter(chunk.contains(id)).delete())
        }
    }

    /// "Clear history": favorites are a separate collection and survive.
    func deleteNonFavoriteItems() async throws {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }
        try db.run(clipboardItems.filter(isFavorite == false).delete())
    }

    // List queries skip the `data` blob column — images can be megabytes each
    // and the list only needs metadata. Use fetchItemData(id:) to load blobs on demand.
    private var listColumns: [Expressible] {
        [id, createdAt, lastUsedAt, type, content, dataHash, sourceApp, tags, embedding, isFavorite, favoritedAt]
    }

    private var sortKey: SQLite.Expression<Double> {
        lastUsedAt ?? createdAt
    }

    func fetchAllClipboardItems() async throws -> [ClipboardItem] {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        return try db.prepare(clipboardItems.select(listColumns).order(sortKey.desc))
            .compactMap(clipboardItem(from:))
    }

    func fetchItemData(id itemID: UUID) async throws -> Data? {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = clipboardItems.select(data).filter(id == itemID.uuidString)
        guard let row = try db.pluck(query) else { return nil }
        return row[data]
    }

    /// nil for a row whose id isn't a UUID (legacy/tampered data) — one bad row
    /// must not blank the whole history.
    private func clipboardItem(from row: Row) -> ClipboardItem? {
        guard let itemID = UUID(uuidString: row[id]) else {
            print("⚠️ Skipping clipboard row with invalid id: \(row[id])")
            return nil
        }

        let tagsArray = (try? JSONDecoder().decode([String].self, from: Data(row[tags].utf8))) ?? []

        var item = ClipboardItem(
            type: row[type],
            content: row[content],
            data: nil,
            sourceApp: row[sourceApp]
        )

        item.id = itemID
        item.createdAt = Date(timeIntervalSince1970: row[createdAt])
        item.dataHash = row[dataHash]
        if let lastUsedAtTimestamp = row[lastUsedAt] {
            item.lastUsedAt = Date(timeIntervalSince1970: lastUsedAtTimestamp)
        }
        item.tags = tagsArray
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

        // Same ordering rule as ClipboardStore.load(): favoritedAt with
        // createdAt fallback — legacy favorites may have a NULL favoritedAt
        return try db.prepare(clipboardItems.select(listColumns).filter(isFavorite == true).order((favoritedAt ?? createdAt).desc))
            .compactMap(clipboardItem(from:))
    }
}

enum DatabaseError: Error {
    case connectionFailed
}
