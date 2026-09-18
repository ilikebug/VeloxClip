import XCTest
import SQLite
@testable import VeloxClip

final class DatabaseManagerTests: XCTestCase {
    func testFetchSkipsRowsWithInvalidIDInsteadOfFailingWholeQuery() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)
        let good = ClipboardItem(type: "text", content: "good")
        try await db.insertClipboardItem(good)

        let connection = try Connection(url.path)
        try connection.run("""
            INSERT INTO clipboard_items (id, createdAt, type, content, isFavorite)
            VALUES (?, ?, ?, ?, 1)
            """, "not-a-uuid", Date().timeIntervalSince1970, "text", "corrupt")

        let all = try await db.fetchAllClipboardItems()
        XCTAssertEqual(all.map(\.id), [good.id])
        let favorites = try await db.fetchFavoriteItems()
        XCTAssertEqual(favorites.count, 0)
    }

    func testDatabaseUsesWALJournalMode() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "x"))

        let mode = try Connection(url.path).scalar("PRAGMA journal_mode") as? String
        XCTAssertEqual(mode?.lowercased(), "wal")
    }

    func testInsertingSameItemTwiceIsIdempotent() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let item = ClipboardItem(type: "text", content: "once")
        try await db.insertClipboardItem(item)
        try await db.insertClipboardItem(item)

        let all = try await db.fetchAllClipboardItems()
        XCTAssertEqual(all.count, 1)
    }

    func testDeleteClipboardItemsRemovesAllGivenIDs() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let items = (0..<3).map { ClipboardItem(type: "text", content: "\($0)") }
        for item in items { try await db.insertClipboardItem(item) }

        try await db.deleteClipboardItems(ids: [items[0].id, items[2].id])

        let remaining = try await db.fetchAllClipboardItems()
        XCTAssertEqual(remaining.map(\.id), [items[1].id])
    }

    func testDeleteNonFavoriteItemsKeepsFavorites() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        var favorite = ClipboardItem(type: "text", content: "keep")
        favorite.isFavorite = true
        let regular = ClipboardItem(type: "text", content: "drop")
        try await db.insertClipboardItem(favorite)
        try await db.insertClipboardItem(regular)

        try await db.deleteNonFavoriteItems()

        let remaining = try await db.fetchAllClipboardItems()
        XCTAssertEqual(remaining.map(\.id), [favorite.id])
    }

    func testTouchItemPersistsLastUsedAtAndOrdersByIt() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        var older = ClipboardItem(type: "text", content: "older")
        older.createdAt = Date(timeIntervalSinceNow: -7200)
        let newer = ClipboardItem(type: "text", content: "newer")
        try await db.insertClipboardItem(older)
        try await db.insertClipboardItem(newer)

        let usedAt = Date()
        try await db.touchItem(id: older.id, lastUsedAt: usedAt)

        let all = try await db.fetchAllClipboardItems()
        XCTAssertEqual(all.map(\.id), [older.id, newer.id], "COALESCE(lastUsedAt, createdAt) DESC")
        XCTAssertEqual(all.first?.createdAt.timeIntervalSince1970 ?? 0, older.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(all.first?.lastUsedAt?.timeIntervalSince1970 ?? 0, usedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testNarrowUpdatesDoNotTouchFavoriteColumns() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let item = ClipboardItem(type: "image", data: Data([1, 2, 3]))
        try await db.insertClipboardItem(item)
        try await db.toggleFavorite(id: item.id)

        try await db.updateDetectedMetadata(id: item.id, tags: ["URL"], embedding: Data([9]))
        try await db.updateContent(id: item.id, content: "ocr text", tags: ["URL", "OCR"])
        try await db.updateTags(id: item.id, tags: ["custom"])

        let stored = try await db.fetchAllClipboardItems().first
        XCTAssertEqual(stored?.isFavorite, true)
        XCTAssertNotNil(stored?.favoritedAt)
        XCTAssertEqual(stored?.content, "ocr text")
        XCTAssertEqual(stored?.tags, ["custom"])
        XCTAssertEqual(stored?.embedding, Data([9]))
        // Blob untouched by the narrow updates
        let blob = try await db.fetchItemData(id: item.id)
        XCTAssertEqual(blob, Data([1, 2, 3]))
    }

    func testInitializationIsRetriedAfterMigrationFailure() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        // A legacy schema on a read-only FILE: the connection opens fine, then the
        // WAL pragma / ALTER TABLE migration throws — the session must not be
        // stuck half-initialized; the next call after the cause is gone retries
        try Connection(url.path).run("CREATE TABLE clipboard_items (id TEXT PRIMARY KEY NOT NULL, createdAt DOUBLE NOT NULL, type TEXT NOT NULL, content TEXT, data BLOB, sourceApp TEXT)")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let db = DatabaseManager(databaseURL: url)
        do {
            try await db.insertClipboardItem(ClipboardItem(type: "text", content: "first"))
            XCTFail("expected the write to fail while the database file is read-only")
        } catch {}

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "second"))
        let all = try await db.fetchAllClipboardItems()
        XCTAssertEqual(all.map(\.content), ["second"])
    }

    func testLegacyDatabaseIsRelocatedToNewPath() async throws {
        let target = TestSupport.makeDatabaseURL(#function)
        let legacyDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VeloxClipTests-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacy = legacyDir.appendingPathComponent("velox.db")
        let legacyID = UUID()
        // The real case: a database written by an older app version that is no
        // longer running (rollback journal, connection closed). A still-open WAL
        // database cannot be relocated safely at all — SQLite reports I/O errors.
        do {
            let connection = try Connection(legacy.path)
            try connection.run("CREATE TABLE clipboard_items (id TEXT PRIMARY KEY NOT NULL, createdAt DOUBLE NOT NULL, type TEXT NOT NULL, content TEXT, data BLOB, sourceApp TEXT)")
            try connection.run("INSERT INTO clipboard_items (id, createdAt, type, content) VALUES (?, ?, ?, ?)",
                               legacyID.uuidString, Date().timeIntervalSince1970, "text", "from legacy")
        }

        let db = DatabaseManager(databaseURL: target, legacyDatabaseURLs: [legacy])
        let all = try await db.fetchAllClipboardItems()

        XCTAssertEqual(all.map(\.id), [legacyID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }
}
