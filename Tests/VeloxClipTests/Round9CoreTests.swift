import XCTest
import AppKit
import SQLite
@testable import VeloxClip

/// Round-9 low-priority findings in the core: the stored count, search ranking,
/// the launch window, the trim query plan and failed copies.
@MainActor
final class Round9CoreTests: XCTestCase {

    private func makeStore(_ name: String) async -> (ClipboardStore, DatabaseManager) {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(name))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        return (ClipboardStore(dbManager: db, settings: settings, shouldLoad: false), db)
    }

    // MARK: - Menu-bar count lagged behind a new copy

    /// `storedItemCount` was refreshed on load, delete and limit change, but not
    /// after an insert, so the menu-bar History card lagged a copy behind.
    func testStoredCountFollowsANewItem() async throws {
        let (store, _) = await makeStore(#function)
        store.addItem(ClipboardItem(type: "text", content: "fresh copy"))

        try await TestSupport.waitUntil {
            await MainActor.run { store.storedItemCount == 1 }
        }
        XCTAssertEqual(store.storedItemCount, 1)
    }

    // MARK: - Ranking comparator was not transitive

    /// "Within 0.001" chains: a ~ b and b ~ c, yet c outscores a. With recency
    /// a > b > c that is a cycle (a before b before c before a), so the result
    /// depended on the order the rows came in.
    func testRankIsIndependentOfInputOrder() {
        func row(_ text: String, _ lastUsed: TimeInterval) -> ClipboardItem {
            var item = ClipboardItem(type: "text", content: text)
            item.lastUsedAt = Date(timeIntervalSince1970: lastUsed)
            return item
        }
        let a = row("a", 3_000), b = row("b", 2_000), c = row("c", 1_000)
        let scores = [a.id: 0.9000, b.id: 0.9008, c.id: 0.9016]

        let orders = [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]]
        let results = Set(orders.map { ClipboardSearchViewModel.rank(scores, baseItems: $0).map(\.id) })
        XCTAssertEqual(results.count, 1, "ranking must not depend on input order — got \(results)")
    }

    // MARK: - Recently used favorites crowded history out of the launch window

    /// The launch read is bounded and favorites take slots in it, so enough
    /// recently used favorites left no ordinary rows on screen at all.
    func testRecentFavoritesDoNotPushHistoryOutOfTheLoad() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        var historyIDs: [UUID] = []
        for i in 0..<5 {
            var item = ClipboardItem(type: "text", content: "history \(i)")
            item.createdAt = Date(timeIntervalSince1970: TimeInterval(1_000 + i))
            historyIDs.append(item.id)
            try await db.insertClipboardItem(item)
        }
        for i in 0..<25 {
            var fav = ClipboardItem(type: "text", content: "fav \(i)")
            fav.createdAt = Date(timeIntervalSince1970: TimeInterval(500 + i))
            fav.lastUsedAt = Date(timeIntervalSince1970: TimeInterval(9_000 + i))   // used recently
            fav.isFavorite = true
            fav.favoritedAt = fav.createdAt
            try await db.insertClipboardItem(fav)
        }

        let loaded = try await db.fetchAllClipboardItems(limit: 20)
        XCTAssertEqual(loaded.filter { historyIDs.contains($0.id) }.count, 5,
                       "ordinary history must survive a window full of recently used favorites")
        let keys = loaded.map { $0.lastUsedAt ?? $0.createdAt }
        XCTAssertEqual(keys, keys.sorted(by: >), "the merged window must stay in recency order")
    }

    // MARK: - History trim sorted in a temp B-tree

    func testTrimQueryIsServedByAnIndex() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "x"))

        // The same query DatabaseManager.trimNonFavorites builds
        let id = SQLite.Expression<String>("id")
        let sortKey = SQLite.Expression<Double?>("lastUsedAt") ?? SQLite.Expression<Double>("createdAt")
        let query = Table("clipboard_items")
            .select(id)
            .filter(SQLite.Expression<Bool>("isFavorite") == false)
            .order(sortKey.desc, id.desc)
            .limit(10)

        let connection = try Connection(url.path)
        var rows: [String] = []
        let sql = query.expression
        for row in try connection.prepare("EXPLAIN QUERY PLAN " + sql.template, sql.bindings) {
            rows.append(row.compactMap { $0 as? String }.joined(separator: " "))
        }
        let detail = rows.joined(separator: " | ")
        XCTAssertFalse(detail.uppercased().contains("TEMP B-TREE"), "trim ordering fell back to a filesort — got: \(detail)")
    }

    // MARK: - A failed copy still moved the item to the top

    func testFailedCopyDoesNotMoveTheItemToTheTop() async throws {
        let (store, _) = await makeStore(#function)
        let newest = ClipboardItem(type: "text", content: "newest")
        let broken = ClipboardItem(type: "image", data: Data("not an image".utf8))
        store.items = [newest, broken]

        let pasteboard = PasteboardService(
            pasteboard: NSPasteboard(name: NSPasteboard.Name("velox-test-\(UUID().uuidString)"))
        )
        PreviewViewModel(pasteboard: pasteboard, store: store).copyToClipboard(broken)

        XCTAssertEqual(store.items.first?.id, newest.id, "an image that never reached the pasteboard was not used")
        XCTAssertNil(store.items.first(where: { $0.id == broken.id })?.lastUsedAt)
    }
}
