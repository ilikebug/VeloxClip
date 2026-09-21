import XCTest
@testable import VeloxClip

/// Opt-in: runs the real maintenance path against a copy of an actual database.
/// VELOXCLIP_VACUUM_DB=/path/to/veloxclip.db swift test --filter RealDatabaseVacuum
final class RealDatabaseVacuumTests: XCTestCase {
    func testVacuumAgainstRealDatabaseCopy() async throws {
        guard let path = ProcessInfo.processInfo.environment["VELOXCLIP_VACUUM_DB"] else {
            throw XCTSkip("set VELOXCLIP_VACUUM_DB to a database copy")
        }
        let url = URL(fileURLWithPath: path)

        func size() -> Int64 {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) as? Int64 ?? 0
        }

        let before = size()
        let db = DatabaseManager(databaseURL: url)
        let rowsBefore = try await db.fetchAllClipboardItems().count
        let favoritesBefore = try await db.fetchFavoriteItems().count

        await db.runDeferredMaintenance()

        let after = size()
        let rowsAfter = try await db.fetchAllClipboardItems().count
        let favoritesAfter = try await db.fetchFavoriteItems().count

        print(String(format: "REAL-DB: %.0f MB -> %.0f MB (rows %d -> %d, favorites %d -> %d)",
                     Double(before) / 1_048_576, Double(after) / 1_048_576,
                     rowsBefore, rowsAfter, favoritesBefore, favoritesAfter))

        XCTAssertEqual(rowsAfter, rowsBefore, "no row may be lost")
        XCTAssertEqual(favoritesAfter, favoritesBefore, "favorites must survive")
        XCTAssertLessThan(after, before, "the file must actually shrink")
    }
}
