import XCTest
import SQLite
@testable import VeloxClip

/// Legacy migration moved whatever sat at the old Velox/Velo path to the live
/// DB path without checking it was an openable database, and never rolled back
/// when the result could not be opened. A partial download or a file truncated
/// by a crash therefore bricked history permanently: the bad file now occupied
/// the target path, the `!fileExists` guard prevented any retry, and every
/// subsequent copy was silently dropped.
final class DatabaseMigrationValidationTests: XCTestCase {

    private func makeLegacyLayout(legacyName: String,
                                  legacyContents: Data,
                                  function: String = #function) throws -> (support: URL, legacy: URL, live: URL) {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("veloxclip-migration-\(abs(function.hashValue))-\(UUID().uuidString)")
        let legacyDir = support.appendingPathComponent("Velox")
        let liveDir = support.appendingPathComponent("VeloxClip")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        let legacy = legacyDir.appendingPathComponent(legacyName)
        try legacyContents.write(to: legacy)
        return (support, legacy, liveDir.appendingPathComponent("veloxclip.db"))
    }

    /// A file that is not a database must not be promoted to the live path.
    func testAnUnopenableLegacyFileIsNotPromoted() throws {
        // Valid SQLite header, garbage body — the shape a truncated copy has.
        var bytes = Data("SQLite format 3\0".utf8)
        bytes.append(Data(repeating: 0xAB, count: 4096))

        let layout = try makeLegacyLayout(legacyName: "velox.db", legacyContents: bytes)
        defer { try? FileManager.default.removeItem(at: layout.support) }

        let migrated = DatabaseManager.migrateLegacyDatabaseForTesting(
            from: layout.legacy, to: layout.live, fileManager: .default
        )

        XCTAssertFalse(migrated, "an unopenable file must not count as a migration")
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.live.path),
                       "the bad file must not occupy the live path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.legacy.path),
                      "it must be rolled back to where it came from")
    }

    /// After a refused migration the app must still be able to store clipboard
    /// items — previously every copy was dropped forever.
    func testCopyingStillWorksAfterARefusedMigration() async throws {
        var bytes = Data("SQLite format 3\0".utf8)
        bytes.append(Data(repeating: 0xCD, count: 2048))

        let layout = try makeLegacyLayout(legacyName: "velox.db", legacyContents: bytes)
        defer { try? FileManager.default.removeItem(at: layout.support) }

        _ = DatabaseManager.migrateLegacyDatabaseForTesting(
            from: layout.legacy, to: layout.live, fileManager: .default
        )

        let db = DatabaseManager(databaseURL: layout.live)
        let item = ClipboardItem(type: "text", content: "copied after the bad migration")
        try await db.insertClipboardItem(item)

        let stored = try await db.fetchAllClipboardItems(limit: nil)
        XCTAssertEqual(stored.count, 1, "a fresh database must be usable")
        XCTAssertEqual(stored.first?.content, "copied after the bad migration")
    }

    /// The happy path must still migrate real data intact.
    func testAHealthyLegacyDatabaseMigratesIntact() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("veloxclip-legacy-good-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let legacyDir = scratch.appendingPathComponent("Velox")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacy = legacyDir.appendingPathComponent("velox.db")
        let live = scratch.appendingPathComponent("VeloxClip/veloxclip.db")
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Build a real database at the legacy path
        let seed = DatabaseManager(databaseURL: legacy)
        for i in 0..<3 {
            try await seed.insertClipboardItem(ClipboardItem(type: "text", content: "legacy \(i)"))
        }
        await seed.closeForTesting()

        let migrated = DatabaseManager.migrateLegacyDatabaseForTesting(
            from: legacy, to: live, fileManager: .default
        )

        XCTAssertTrue(migrated, "a healthy legacy database must migrate")
        let db = DatabaseManager(databaseURL: live)
        let rows = try await db.fetchAllClipboardItems(limit: nil)
        XCTAssertEqual(rows.count, 3, "all legacy rows must survive")
    }
}
