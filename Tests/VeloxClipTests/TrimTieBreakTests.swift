import XCTest
import SQLite
@testable import VeloxClip

/// `trimNonFavorites` picks a cutoff sortKey and deletes `sortKey <= cutoff`.
/// sortKey is COALESCE(lastUsedAt, createdAt) — a Double with no uniqueness
/// guarantee — so every row TIED with the cutoff is swept up too. One tie costs
/// an extra row; a restored backup where every row shares a timestamp loses the
/// entire history.
final class TrimTieBreakTests: XCTestCase {
    private func insert(_ db: DatabaseManager, content: String, at t: TimeInterval,
                        favorite: Bool = false) async throws -> UUID {
        var item = ClipboardItem(type: "text", content: content)
        item.createdAt = Date(timeIntervalSince1970: t)
        item.isFavorite = favorite
        if favorite { item.favoritedAt = item.createdAt }
        try await db.insertClipboardItem(item)
        return item.id
    }

    /// The minimum case: two rows share the cutoff's timestamp.
    func testASingleTieAtTheCutoffKeepsExactlyTheLimit() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        for i in 0..<9 {
            _ = try await insert(db, content: "distinct \(i)", at: TimeInterval(1_000 + i))
        }
        // Two rows sharing one timestamp, positioned to straddle the cutoff
        _ = try await insert(db, content: "tied a", at: 500)
        _ = try await insert(db, content: "tied b", at: 500)

        _ = try await db.trimNonFavorites(keeping: 10)

        let survivors = try await db.fetchAllClipboardItems().count
        XCTAssertEqual(survivors, 10, "a tie at the cutoff must not cost an extra row")
    }

    /// A restored backup or bulk import can give every row one timestamp.
    /// `<= cutoff` then matches the whole table.
    func testIdenticalTimestampsDoNotEraseTheHistory() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        for i in 0..<20 {
            _ = try await insert(db, content: "imported \(i)", at: 1_700_000_000)
        }

        _ = try await db.trimNonFavorites(keeping: 10)

        let survivors = try await db.fetchAllClipboardItems().count
        XCTAssertEqual(survivors, 10, "identical timestamps must not erase the history")
    }

    /// Several rows sharing the cutoff, with distinct rows on either side.
    func testManyRowsSharingTheCutoffAreNotAllDeleted() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        for i in 0..<3 {
            _ = try await insert(db, content: "newer \(i)", at: TimeInterval(100 + i))
        }
        for i in 0..<20 {
            _ = try await insert(db, content: "tied \(i)", at: 50)
        }

        _ = try await db.trimNonFavorites(keeping: 10)

        let survivors = try await db.fetchAllClipboardItems().count
        XCTAssertEqual(survivors, 10, "rows sharing the cutoff must not all be taken")
    }

    /// The control: with strictly distinct keys the trim is exact. This isolates
    /// the failures above to tie handling rather than to the trim in general.
    func testTrimIsExactWithDistinctTimestamps() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        var newest: UUID?
        for i in 0..<25 {
            newest = try await insert(db, content: "item \(i)", at: TimeInterval(1_000 + i))
        }

        let deleted = try await db.trimNonFavorites(keeping: 10)

        XCTAssertEqual(deleted.count, 15)
        let survivors = try await db.fetchAllClipboardItems()
        XCTAssertEqual(survivors.count, 10)
        XCTAssertEqual(survivors.first?.id, newest, "the newest row must survive")
    }

    /// Favorites are exempt even when they share the cutoff timestamp.
    func testFavoritesSharingTheCutoffAreNeverDeleted() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        var favIDs: [UUID] = []
        for i in 0..<5 {
            favIDs.append(try await insert(db, content: "fav \(i)", at: 50, favorite: true))
        }
        for i in 0..<20 {
            _ = try await insert(db, content: "plain \(i)", at: 50)
        }

        let deleted = try await db.trimNonFavorites(keeping: 5)

        XCTAssertTrue(Set(deleted).isDisjoint(with: Set(favIDs)), "favorites are exempt")
        let remaining = try await db.fetchAllClipboardItems()
        XCTAssertEqual(remaining.filter { $0.isFavorite }.count, 5)
        XCTAssertEqual(remaining.filter { !$0.isFavorite }.count, 5)
    }

    /// The returned ids must be exactly what was deleted, or the store's
    /// in-memory prune drifts from the table.
    func testReturnedIDsMatchWhatWasActuallyDeleted() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        for i in 0..<12 {
            _ = try await insert(db, content: "tied \(i)", at: 777)
        }

        let deleted = Set(try await db.trimNonFavorites(keeping: 4))
        let remaining = Set(try await db.fetchAllClipboardItems().map(\.id))

        XCTAssertEqual(remaining.count, 4)
        XCTAssertTrue(deleted.isDisjoint(with: remaining),
                      "no id may be both reported deleted and still present")
        XCTAssertEqual(deleted.count, 8)
    }
}
