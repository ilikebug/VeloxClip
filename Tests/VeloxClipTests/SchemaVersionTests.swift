import XCTest
import SQLite
@testable import VeloxClip

final class SchemaVersionTests: XCTestCase {
    func testFreshDatabaseIsStampedWithTheCurrentVersion() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "x"))

        let version = try Connection(url.path).scalar("PRAGMA user_version") as? Int64
        XCTAssertEqual(Int(version ?? -1), DatabaseManager.currentSchemaVersion)
    }

    /// A downgrade used to be undetectable: the old binary opened the newer DB,
    /// ignored columns it didn't know, and wrote rows the newer build would then
    /// read with defaults. Refuse the file instead.
    func testDatabaseFromANewerBuildIsRefusedRatherThanWritten() async throws {
        let url = TestSupport.makeDatabaseURL(#function)

        // Simulate a file written by a future version.
        let seed = try Connection(url.path)
        try seed.run("PRAGMA user_version = \(DatabaseManager.currentSchemaVersion + 5)")
        try seed.run("CREATE TABLE clipboard_items (id TEXT PRIMARY KEY NOT NULL, createdAt DOUBLE NOT NULL, type TEXT NOT NULL, content TEXT, data BLOB, sourceApp TEXT)")

        let db = DatabaseManager(databaseURL: url)
        do {
            try await db.insertClipboardItem(ClipboardItem(type: "text", content: "should not land"))
            XCTFail("expected the write to be refused against a newer schema")
        } catch {
            // connectionFailed is the surfaced error: initialization bailed out.
        }

        // Nothing was written, and the future version marker is intact.
        let count = try seed.scalar("SELECT COUNT(*) FROM clipboard_items") as? Int64
        XCTAssertEqual(count, 0, "no row may be written to a database from a newer build")
        let version = try seed.scalar("PRAGMA user_version") as? Int64
        XCTAssertEqual(Int(version ?? -1), DatabaseManager.currentSchemaVersion + 5,
                       "the newer version marker must not be downgraded")
    }

    func testExistingUnversionedDatabaseIsUpgradedInPlace() async throws {
        let url = TestSupport.makeDatabaseURL(#function)

        // A pre-versioning database: user_version still 0, legacy column set.
        let seed = try Connection(url.path)
        try seed.run("CREATE TABLE clipboard_items (id TEXT PRIMARY KEY NOT NULL, createdAt DOUBLE NOT NULL, type TEXT NOT NULL, content TEXT, data BLOB, sourceApp TEXT)")
        XCTAssertEqual(try seed.scalar("PRAGMA user_version") as? Int64, 0)

        let db = DatabaseManager(databaseURL: url)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "upgraded"))

        let version = try Connection(url.path).scalar("PRAGMA user_version") as? Int64
        XCTAssertEqual(Int(version ?? -1), DatabaseManager.currentSchemaVersion)
        let items = try await db.fetchAllClipboardItems()
        XCTAssertEqual(items.count, 1, "an unversioned database must still be usable")
    }
}
