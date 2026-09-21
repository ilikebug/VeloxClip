import XCTest
import SQLite
@testable import VeloxClip

final class DatabaseManagerMigrationTests: XCTestCase {
    func testLegacyClipboardTableIsMigratedBeforeUse() async throws {
        let databaseURL = TestSupport.makeDatabaseURL(#function)
        try createLegacyDatabase(at: databaseURL)

        let databaseManager = DatabaseManager(databaseURL: databaseURL)
        let items = try await databaseManager.fetchAllClipboardItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.content, "legacy")
        XCTAssertEqual(items.first?.tags, [String]())
        XCTAssertNil(items.first?.embedding)

        let connection = try Connection(databaseURL.path)
        let columns = try connection.prepare("PRAGMA table_info(clipboard_items)").compactMap { row in
            row[1] as? String
        }

        XCTAssertTrue(columns.contains("tags"))
        XCTAssertTrue(columns.contains("embedding"))
        XCTAssertTrue(columns.contains("isFavorite"))
        XCTAssertTrue(columns.contains("favoritedAt"))
        XCTAssertTrue(columns.contains("lastUsedAt"))
        XCTAssertTrue(columns.contains("dataHash"))
    }

    func testLegacyBlobRowsGetDataHashBackfilled() async throws {
        let databaseURL = TestSupport.makeDatabaseURL(#function)
        try createLegacyDatabase(at: databaseURL)

        // Add a legacy row that carries a blob but (obviously) no dataHash column value
        let blob = Data([7, 7, 7])
        let connection = try Connection(databaseURL.path)
        try connection.run("""
            INSERT INTO clipboard_items (id, createdAt, type, data, sourceApp)
            VALUES (?, ?, ?, ?, ?)
            """, UUID().uuidString, Date().timeIntervalSince1970, "image", Blob(bytes: [UInt8](blob)), "Tests")

        let databaseManager = DatabaseManager(databaseURL: databaseURL)
        // The backfill is no longer part of initialization — it scans every blob,
        // which blocked the first history load on a large upgrade.
        await databaseManager.runDeferredMaintenance()
        let items = try await databaseManager.fetchAllClipboardItems()

        let imageItem = items.first { $0.type == "image" }
        XCTAssertEqual(imageItem?.dataHash, ClipboardItem.hash(of: blob))
    }

    /// A WAL-mode database keeps un-checkpointed rows in its sidecars. The move
    /// must carry them, and must be all-or-nothing.
    func testLegacyMigrationCarriesWALSidecars() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VeloxClipWAL-\(UUID().uuidString)", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("Velox", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        let legacyDB = legacyDirectory.appendingPathComponent("velox.db")
        try createLegacyDatabase(at: legacyDB)

        // Stand-in sidecars; the migration must move them alongside the DB.
        let legacyWAL = URL(fileURLWithPath: legacyDB.path + "-wal")
        let legacySHM = URL(fileURLWithPath: legacyDB.path + "-shm")
        try Data([1, 2, 3]).write(to: legacyWAL)
        try Data([4, 5]).write(to: legacySHM)

        // An unrelated file the previous version kept — deleting the whole
        // legacy directory used to take it with the migration.
        let bystander = legacyDirectory.appendingPathComponent("exports.json")
        try Data("{}".utf8).write(to: bystander)

        let target = root.appendingPathComponent("VeloxClip", isDirectory: true)
            .appendingPathComponent("veloxclip.db")
        _ = DatabaseManager(databaseURL: target, legacyDatabaseURLs: [legacyDB])

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: target.path), "the database must be migrated")
        XCTAssertTrue(fm.fileExists(atPath: target.path + "-wal"), "the WAL sidecar must move too")
        XCTAssertTrue(fm.fileExists(atPath: target.path + "-shm"), "the SHM sidecar must move too")
        XCTAssertFalse(fm.fileExists(atPath: legacyDB.path), "the legacy database must be gone")
        XCTAssertTrue(fm.fileExists(atPath: bystander.path),
                      "migration must not delete unrelated files in the legacy directory")
    }

    private func createLegacyDatabase(at url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let connection = try Connection(url.path)
        try connection.run("""
            CREATE TABLE clipboard_items (
                id TEXT PRIMARY KEY NOT NULL,
                createdAt DOUBLE NOT NULL,
                type TEXT NOT NULL,
                content TEXT,
                data BLOB,
                sourceApp TEXT
            )
            """)
        try connection.run("""
            INSERT INTO clipboard_items (id, createdAt, type, content, sourceApp)
            VALUES (?, ?, ?, ?, ?)
            """, UUID().uuidString, Date().timeIntervalSince1970, "text", "legacy", "Tests")
    }

}
