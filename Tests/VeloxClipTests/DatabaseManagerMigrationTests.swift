import XCTest
import SQLite
@testable import VeloxClip

final class DatabaseManagerMigrationTests: XCTestCase {
    func testLegacyClipboardTableIsMigratedBeforeUse() async throws {
        let databaseURL = makeDatabaseURL(directoryName: #function)
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
        XCTAssertTrue(columns.contains("summary"))
        XCTAssertTrue(columns.contains("isSensitive"))
        XCTAssertTrue(columns.contains("embedding"))
        XCTAssertTrue(columns.contains("isFavorite"))
        XCTAssertTrue(columns.contains("favoritedAt"))
        XCTAssertTrue(columns.contains("lastUsedAt"))
        XCTAssertTrue(columns.contains("dataHash"))
    }

    func testLegacyBlobRowsGetDataHashBackfilled() async throws {
        let databaseURL = makeDatabaseURL(directoryName: #function)
        try createLegacyDatabase(at: databaseURL)

        // Add a legacy row that carries a blob but (obviously) no dataHash column value
        let blob = Data([7, 7, 7])
        let connection = try Connection(databaseURL.path)
        try connection.run("""
            INSERT INTO clipboard_items (id, createdAt, type, data, sourceApp)
            VALUES (?, ?, ?, ?, ?)
            """, UUID().uuidString, Date().timeIntervalSince1970, "image", Blob(bytes: [UInt8](blob)), "Tests")

        let databaseManager = DatabaseManager(databaseURL: databaseURL)
        let items = try await databaseManager.fetchAllClipboardItems()

        let imageItem = items.first { $0.type == "image" }
        XCTAssertEqual(imageItem?.dataHash, ClipboardItem.hash(of: blob))
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

    private func makeDatabaseURL(directoryName: String) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root.appendingPathComponent("VeloxClipTests-\(directoryName)-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent("veloxclip.db")
    }
}
