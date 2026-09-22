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
                if migrateLegacyDatabase(from: legacyDB, to: dbPath, fileManager: fileManager) {
                    break
                }
            }
        }

        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try? fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }
    }

    /// Moves a legacy database and its WAL sidecars, all-or-nothing.
    ///
    /// The sidecars move FIRST. A WAL-mode database keeps un-checkpointed rows
    /// in them, so a half-done move that lands the main file without its WAL
    /// silently drops the newest history — and the previous version did exactly
    /// that, because a throw on the sidecar came after the main file had already
    /// moved and the only handling was a `print`. On any failure everything is
    /// moved back and the legacy path is left intact.
    private static func migrateLegacyDatabase(from legacyDB: URL, to dbPath: URL, fileManager: FileManager) -> Bool {
        let suffixes = ["-wal", "-shm"]
        var completed: [(from: URL, to: URL)] = []

        func rollback() {
            for move in completed.reversed() {
                try? fileManager.moveItem(at: move.to, to: move.from)
            }
        }

        do {
            try fileManager.createDirectory(at: dbPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            for suffix in suffixes {
                let source = URL(fileURLWithPath: legacyDB.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = URL(fileURLWithPath: dbPath.path + suffix)
                try fileManager.moveItem(at: source, to: destination)
                completed.append((from: source, to: destination))
            }

            try fileManager.moveItem(at: legacyDB, to: dbPath)
            completed.append((from: legacyDB, to: dbPath))
        } catch {
            print("⚠️ Migration failed from \(legacyDB.path): \(error) — rolling back")
            rollback()
            return false
        }

        print("✅ Migrated database from \(legacyDB.lastPathComponent) to \(dbPath.path)")

        // Remove only what we migrated. This used to delete the whole legacy
        // directory, taking any other files the previous version kept there.
        let legacyDirectory = legacyDB.deletingLastPathComponent()
        if let remaining = try? fileManager.contentsOfDirectory(atPath: legacyDirectory.path), remaining.isEmpty {
            try? fileManager.removeItem(at: legacyDirectory)
        }
        return true
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

    /// Highest schema this binary understands. Bump it when adding a migration.
    static let currentSchemaVersion = 1

    /// Refuses to open a database written by a newer build.
    ///
    /// Without this, an older binary opened a newer DB, silently ignored the
    /// columns it didn't know about, and wrote rows the newer build would later
    /// read with defaults — data loss with no warning. Additive column migrations
    /// stay driven by `PRAGMA table_info` (idempotent and self-healing); the
    /// version is the guard rail for everything that isn't additive.
    private func applySchemaVersion() throws {
        guard let db = db else { return }

        let existing = Int(try db.scalar("PRAGMA user_version") as? Int64 ?? 0)

        if existing > Self.currentSchemaVersion {
            throw DatabaseError.schemaTooNew(found: existing, supported: Self.currentSchemaVersion)
        }

        if existing < Self.currentSchemaVersion {
            try db.run("PRAGMA user_version = \(Self.currentSchemaVersion)")
        }
    }

    private func createTables() throws {
        guard let db = db else { return }

        // Version check first: refuse a newer schema before touching anything.
        try applySchemaVersion()

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

        // Indices must match the ORDER BY the list queries actually use.
        // A plain index on createdAt cannot satisfy an ORDER BY over
        // COALESCE(lastUsedAt, createdAt), so every launch was a full scan
        // plus a filesort. These are expression indices on the real sort keys.
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_items_recency
            ON clipboard_items(COALESCE(lastUsedAt, createdAt) DESC)
            """)
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_items_fav_recency
            ON clipboard_items(isFavorite, COALESCE(favoritedAt, createdAt) DESC)
            """)
        // Superseded by idx_items_recency; drop it so we don't pay to maintain it.
        try db.run("DROP INDEX IF EXISTS index_clipboard_items_on_createdAt")
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
    }

    // One-time backfill so hash-based dedup also covers rows created before the dataHash column existed.
    // Guarded by a settings flag — new rows always get a hash on insert, so once this has run
    // there is nothing left to scan on subsequent launches.
    //
    // Deliberately NOT part of ensureInitialized: on the first launch after an
    // upgrade with a large image history this reads every blob and used to issue
    // one auto-committed UPDATE (one fsync) per row, blocking every other caller
    // of the actor — settings load, history load, inserts — behind it. The app
    // looked hung with an empty history. Call `runDeferredMaintenance()` after
    // the first successful load instead.
    func runDeferredMaintenance() async {
        do {
            await ensureInitialized()
            try backfillDataHashesIfNeeded()
            _ = try await vacuumIfNeeded()
        } catch {
            print("Deferred maintenance failed: \(error)")
        }
    }

    /// Fraction of the file that must be free pages before a rewrite is worth it.
    private static let vacuumFreePageThreshold = 0.25
    /// Below this there is nothing meaningful to reclaim, whatever the ratio.
    private static let vacuumMinimumFreeBytes = 8 * 1_024 * 1_024

    /// Returns freed pages to the filesystem.
    ///
    /// SQLite marks pages free on DELETE and reuses them, but never shrinks the
    /// file. History-limit trimming and "clear history" delete constantly, so
    /// the database only ever grew: a real install reached 444 MB while holding
    /// 12 MB of data — 97% free pages.
    ///
    /// VACUUM rewrites the whole file, so it is gated on there being something
    /// substantial to reclaim; otherwise every launch would pay a full rewrite.
    @discardableResult
    func vacuumIfNeeded() async throws -> Bool {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        // Fold the WAL back in first, or its pages look "in use" and the
        // freelist reads far smaller than it really is.
        _ = try? db.scalar("PRAGMA wal_checkpoint(TRUNCATE)")

        let pageCount = Int(try db.scalar("PRAGMA page_count") as? Int64 ?? 0)
        let freeCount = Int(try db.scalar("PRAGMA freelist_count") as? Int64 ?? 0)
        let pageSize = Int(try db.scalar("PRAGMA page_size") as? Int64 ?? 0)
        guard pageCount > 0, pageSize > 0 else { return false }

        let freeBytes = freeCount * pageSize
        let ratio = Double(freeCount) / Double(pageCount)
        guard ratio >= Self.vacuumFreePageThreshold, freeBytes >= Self.vacuumMinimumFreeBytes else {
            return false
        }

        try db.run("VACUUM")
        // VACUUM rebuilds the file; make sure it comes back in WAL mode, which
        // is what keeps readers from blocking the writer.
        try db.run("PRAGMA journal_mode=WAL")
        // And checkpoint again: in WAL mode the rebuilt pages land in the WAL,
        // so without this the main file keeps its old size and nothing is
        // actually returned to the filesystem.
        _ = try? db.scalar("PRAGMA wal_checkpoint(TRUNCATE)")

        let reclaimed = Double(freeBytes) / 1_048_576
        print("🧹 Reclaimed \(String(format: "%.0f", reclaimed)) MB of free pages")
        return true
    }

    private func backfillDataHashesIfNeeded() throws {
        guard let db = db else { return }

        let backfillFlag = "dataHashBackfillDone"
        if try db.pluck(appSettings.filter(key == backfillFlag)) != nil { return }

        // Hash outside the write so the transaction is short, then apply every
        // UPDATE in ONE commit — this used to be one auto-committed write (one
        // fsync) per row.
        let pending = clipboardItems.select(id, data).filter(dataHash == nil && data != nil)
        var hashes: [(rowID: String, hash: String)] = []
        for row in try db.prepare(pending) {
            guard let blob = row[data] else { continue }
            hashes.append((rowID: row[id], hash: ClipboardItem.hash(of: blob)))
        }

        let items = clipboardItems
        let idColumn = id
        let hashColumn = dataHash
        let settingsTable = appSettings
        let keyColumn = key
        let valueColumn = value

        try db.transaction {
            for entry in hashes {
                try db.run(items.filter(idColumn == entry.rowID).update(hashColumn <- entry.hash))
            }
            try db.run(settingsTable.insert(or: .replace, keyColumn <- backfillFlag, valueColumn <- "1"))
        }
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

    /// Deletes non-favorite rows beyond the newest `keeping`, in SQL.
    ///
    /// The in-memory trim can only see the rows that were loaded, and the
    /// initial read is bounded — so anything past that window would otherwise
    /// stay on disk forever, invisible and taking space.
    func trimNonFavorites(keeping limit: Int) async throws {
        guard limit > 0 else { return }
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        let survivors = clipboardItems
            .select(id)
            .filter(isFavorite == false)
            .order(sortKey.desc)
            .limit(limit)
        let keepIDs = try db.prepare(survivors).map { $0[id] }

        try db.run(
            clipboardItems
                .filter(isFavorite == false && !keepIDs.contains(id))
                .delete()
        )
    }

    // List queries skip the `data` blob column — images can be megabytes each
    // and the list only needs metadata. Use fetchItemData(id:) to load blobs on demand.
    //
    // `embedding` is skipped for the same reason: it is a per-item vector blob
    // that the list never renders, and pulling every one of them at launch kept
    // the whole history's vectors permanently resident. Semantic search loads
    // them on demand via fetchEmbeddings(ids:).
    private var listColumns: [Expressible] {
        [id, createdAt, lastUsedAt, type, content, dataHash, sourceApp, tags, isFavorite, favoritedAt]
    }

    private var sortKey: SQLite.Expression<Double> {
        lastUsedAt ?? createdAt
    }

    /// `limit` bounds how many rows are read into memory at launch. Nil reads
    /// everything — used by tests and by callers that genuinely need the whole
    /// table. `ClipboardStore` passes the configured history limit plus
    /// headroom, because favorites do not count against that limit.
    func fetchAllClipboardItems(limit: Int? = nil) async throws -> [ClipboardItem] {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        var query = clipboardItems.select(listColumns).order(sortKey.desc)
        if let limit, limit > 0 {
            query = query.limit(limit)
        }
        return try db.prepare(query).compactMap(clipboardItem(from:))
    }

    func fetchItemData(id itemID: UUID) async throws -> Data? {
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = clipboardItems.select(data).filter(id == itemID.uuidString)
        guard let row = try db.pluck(query) else { return nil }
        return row[data]
    }

    /// Embeddings for the given items, loaded on demand by semantic search.
    /// Chunked to stay under SQLite's bound-variable limit, like the bulk delete.
    func fetchEmbeddings(ids: [UUID]) async throws -> [UUID: Data] {
        guard !ids.isEmpty else { return [:] }
        await ensureInitialized()
        guard let db = db else { throw DatabaseError.connectionFailed }

        var result: [UUID: Data] = [:]
        let chunkSize = 500
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = ids[start..<min(start + chunkSize, ids.count)].map(\.uuidString)
            let query = clipboardItems.select(id, embedding)
                .filter(chunk.contains(id) && embedding != nil)
            for row in try db.prepare(query) {
                guard let itemID = UUID(uuidString: row[id]), let vector = row[embedding] else { continue }
                result[itemID] = vector
            }
        }
        return result
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
        // `embedding` is deliberately not in listColumns — see the comment there.
        item.embedding = nil
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
    /// The file was written by a newer build; writing to it would corrupt data
    /// the current binary doesn't understand.
    case schemaTooNew(found: Int, supported: Int)
}
