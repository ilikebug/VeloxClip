import XCTest
import SQLite
@testable import VeloxClip

/// SQLite marks pages free on DELETE but never returns them to the filesystem.
/// History trimming and "clear history" delete constantly, so the file only
/// ever grew — a real install reached 444 MB holding 12 MB of data (97% free
/// pages) because nothing ever ran VACUUM.
final class DatabaseVacuumTests: XCTestCase {
    private func fileSize(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int64 ?? 0
    }

    private func freePageRatio(_ url: URL) throws -> Double {
        let c = try Connection(url.path)
        let pages = Double(try c.scalar("PRAGMA page_count") as? Int64 ?? 0)
        let free = Double(try c.scalar("PRAGMA freelist_count") as? Int64 ?? 0)
        return pages > 0 ? free / pages : 0
    }

    /// Fills the DB with blobs, deletes them, and asserts maintenance gives the
    /// space back to the filesystem.
    func testMaintenanceReclaimsSpaceAfterDeletes() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)

        // ~16 MB of blobs, then delete all of it
        var ids: [UUID] = []
        for i in 0..<16 {
            var item = ClipboardItem(type: "image", data: Data(repeating: UInt8(i), count: 1_024 * 1_024))
            item.content = nil
            ids.append(item.id)
            try await db.insertClipboardItem(item)
        }
        let grownSize = try fileSize(url)
        XCTAssertGreaterThan(grownSize, 8 * 1_024 * 1_024, "precondition: the file should have grown")

        try await db.deleteClipboardItems(ids: ids)
        // Checkpoint so the deletes are in the main file, not just the WAL
        _ = try Connection(url.path).scalar("PRAGMA wal_checkpoint(TRUNCATE)")

        let ratioBefore = try freePageRatio(url)
        XCTAssertGreaterThan(ratioBefore, 0.5, "precondition: deletes should leave mostly free pages")

        await db.runDeferredMaintenance()

        let reclaimedSize = try fileSize(url)
        XCTAssertLessThan(reclaimedSize, grownSize / 2,
                          "maintenance must return freed pages to the filesystem")
        let ratioAfter = try freePageRatio(url)
        XCTAssertLessThan(ratioAfter, 0.1, "the freelist should be essentially empty after a vacuum")
    }

    /// VACUUM rewrites the entire file, so it must not run when there is little
    /// to reclaim — otherwise every launch pays a full rewrite.
    func testVacuumIsSkippedWhenThereIsLittleToReclaim() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "small"))

        let didVacuum = try await db.vacuumIfNeeded()
        XCTAssertFalse(didVacuum, "a healthy database must not be rewritten")
    }

    func testVacuumRunsWhenTheFreelistIsLarge() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)

        var ids: [UUID] = []
        for i in 0..<16 {
            let item = ClipboardItem(type: "image", data: Data(repeating: UInt8(i), count: 1_024 * 1_024))
            ids.append(item.id)
            try await db.insertClipboardItem(item)
        }
        try await db.deleteClipboardItems(ids: ids)
        _ = try Connection(url.path).scalar("PRAGMA wal_checkpoint(TRUNCATE)")

        let didVacuum = try await db.vacuumIfNeeded()
        XCTAssertTrue(didVacuum, "a database that is mostly free pages must be reclaimed")
    }

    /// The data has to survive the rewrite — a vacuum that loses rows is worse
    /// than a large file.
    func testVacuumPreservesRemainingData() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)

        var keeper = ClipboardItem(type: "text", content: "keep me")
        keeper.isFavorite = true
        keeper.favoritedAt = Date()
        keeper.tags = ["important"]
        try await db.insertClipboardItem(keeper)

        var blobKeeper = ClipboardItem(type: "image", data: TestSupport.makePNG(width: 4, height: 4))
        blobKeeper.tags = ["shot"]
        try await db.insertClipboardItem(blobKeeper)

        var doomed: [UUID] = []
        for i in 0..<16 {
            let item = ClipboardItem(type: "image", data: Data(repeating: UInt8(i), count: 1_024 * 1_024))
            doomed.append(item.id)
            try await db.insertClipboardItem(item)
        }
        try await db.deleteClipboardItems(ids: doomed)
        _ = try Connection(url.path).scalar("PRAGMA wal_checkpoint(TRUNCATE)")

        _ = try await db.vacuumIfNeeded()

        let items = try await db.fetchAllClipboardItems()
        XCTAssertEqual(Set(items.map(\.id)), Set([keeper.id, blobKeeper.id]))

        let restored = items.first { $0.id == keeper.id }
        XCTAssertEqual(restored?.content, "keep me")
        XCTAssertEqual(restored?.isFavorite, true)
        XCTAssertEqual(restored?.tags, ["important"])

        // The blob must survive too — it is fetched separately from list rows
        let blob = try await db.fetchItemData(id: blobKeeper.id)
        XCTAssertEqual(blob, TestSupport.makePNG(width: 4, height: 4))
    }

    /// WAL mode is what keeps readers from blocking the writer; VACUUM must not
    /// silently drop the database back to the default journal mode.
    func testVacuumKeepsWALJournalMode() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)

        var ids: [UUID] = []
        for i in 0..<16 {
            let item = ClipboardItem(type: "image", data: Data(repeating: UInt8(i), count: 1_024 * 1_024))
            ids.append(item.id)
            try await db.insertClipboardItem(item)
        }
        try await db.deleteClipboardItems(ids: ids)
        _ = try Connection(url.path).scalar("PRAGMA wal_checkpoint(TRUNCATE)")

        _ = try await db.vacuumIfNeeded()

        let mode = try Connection(url.path).scalar("PRAGMA journal_mode") as? String
        XCTAssertEqual(mode?.lowercased(), "wal")
    }
}
