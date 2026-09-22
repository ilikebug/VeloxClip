import XCTest
@testable import VeloxClip

/// Round-5 findings. Two clusters of stale state.
///
/// 1. `ClipboardSearchViewModel.results` is a snapshot nothing re-derives, so a
///    row deleted from another surface stays visible, stays selectable, and
///    still pastes its content.
/// 2. `ClipboardStore.items` is a bounded window; `favoriteItems` is not. Round 3
///    taught `toggleFavorite`/`markUsed` about that and left the metadata
///    mutators behind, so tag edits and OCR write-back on an old favorite are
///    silently dropped.
@MainActor
final class StaleStateRound5Tests: XCTestCase {

    private func makeStore(limit: Int) async throws -> (ClipboardStore, DatabaseManager) {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        settings.historyLimit = limit
        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: false)
        return (store, db)
    }

    private func makeSearch() -> ClipboardSearchViewModel {
        ClipboardSearchViewModel(
            loadEmbeddings: { _ in [:] },
            embedQuery: { _ in nil },
            similarity: { _, _ in 0 },
            debounce: .milliseconds(1)
        )
    }

    private func runKeywordPass(_ search: ClipboardSearchViewModel,
                                query: String,
                                items: [ClipboardItem]) async {
        let published = expectation(description: "keyword pass")
        published.assertForOverFulfill = false
        search.search(query: query, in: items) { _ in published.fulfill() }
        await fulfillment(of: [published], timeout: 2)
    }

    // MARK: - Cluster 1: stale search results

    /// A row deleted while a search is active must leave the visible results.
    func testSearchResultsDropAnItemDeletedFromAnotherSurface() async throws {
        let (store, db) = try await makeStore(limit: 50)
        let doomed = ClipboardItem(type: "text", content: "beta report")
        let keeper = ClipboardItem(type: "text", content: "beta summary")
        try await db.insertClipboardItem(doomed)
        try await db.insertClipboardItem(keeper)
        store.items = [doomed, keeper]

        let search = makeSearch()
        await runKeywordPass(search, query: "beta", items: store.items)
        XCTAssertEqual(search.results.count, 2, "both rows should match the query")

        // Deleted from another surface: the palette, a swipe, a trim.
        store.items = [keeper]
        search.prune(validIDs: Set(store.items.map(\.id)))

        XCTAssertFalse(
            search.results.contains { $0.id == doomed.id },
            "a deleted row must not stay in the visible search results; got \(search.results.map { $0.content ?? "" })"
        )
        XCTAssertTrue(search.results.contains { $0.id == keeper.id }, "the surviving row must stay")
    }

    /// The pruned list is what the selection repair reads, so ⏎ cannot land on a
    /// deleted row and write its content to the pasteboard.
    func testPrunedResultsCannotYieldADeletedRowForPasting() async throws {
        let (store, db) = try await makeStore(limit: 50)
        let secret = ClipboardItem(type: "text", content: "hunter2-recovery-code")
        let other = ClipboardItem(type: "text", content: "hunter2-notes")
        try await db.insertClipboardItem(secret)
        try await db.insertClipboardItem(other)
        store.items = [secret, other]

        let search = makeSearch()
        await runKeywordPass(search, query: "hunter2", items: store.items)

        store.items = [other]
        search.prune(validIDs: Set(store.items.map(\.id)))

        for row in search.results {
            XCTAssertNotEqual(
                row.content, secret.content,
                "a deleted clip is still reachable for pasting from the search results"
            )
        }
    }

    /// Pruning must not disturb a result set where everything is still live.
    func testPruneKeepsOrderAndContentWhenNothingWasDeleted() async throws {
        let (store, db) = try await makeStore(limit: 50)
        var rows: [ClipboardItem] = []
        for text in ["beta one", "beta two", "beta three"] {
            let item = ClipboardItem(type: "text", content: text)
            try await db.insertClipboardItem(item)
            rows.append(item)
        }
        store.items = rows

        let search = makeSearch()
        await runKeywordPass(search, query: "beta", items: store.items)
        let before = search.results.map(\.id)
        XCTAssertFalse(before.isEmpty)

        search.prune(validIDs: Set(store.items.map(\.id)))

        XCTAssertEqual(search.results.map(\.id), before, "a no-op prune must not reorder or drop rows")
    }

    // MARK: - Cluster 2: favorites outside the bounded window

    /// Exactly the designed steady state: a favorite older than the history
    /// window, so it lives in `favoriteItems` and not in `items`.
    private func makeFavoriteOutsideWindow(
        _ store: ClipboardStore,
        _ db: DatabaseManager,
        tags: [String] = []
    ) async throws -> ClipboardItem {
        var old = ClipboardItem(type: "text", content: "an old favorite")
        old.createdAt = Date(timeIntervalSince1970: 100)
        old.isFavorite = true
        old.favoritedAt = old.createdAt
        old.tags = tags
        try await db.insertClipboardItem(old)
        store.items = []
        store.favoriteItems = [old]
        return old
    }

    func testAddingATagToAFavoriteOutsideTheWindowPersists() async throws {
        let (store, db) = try await makeStore(limit: 5)
        let old = try await makeFavoriteOutsideWindow(store, db)

        await store.updateMetadata(id: old.id, tags: ["receipts"])

        let shown = store.favoriteItems.first { $0.id == old.id }?.tags ?? []
        XCTAssertEqual(shown, ["receipts"], "the new tag must show in the Favorites list immediately")

        let onDisk = try await db.fetchFavoriteItems().first { $0.id == old.id }?.tags
        XCTAssertEqual(onDisk ?? [], ["receipts"], "…and must reach disk")
    }

    func testRemovingATagFromAFavoriteOutsideTheWindowPersists() async throws {
        let (store, db) = try await makeStore(limit: 5)
        let old = try await makeFavoriteOutsideWindow(store, db, tags: ["OCR", "keepme"])

        await store.updateMetadata(id: old.id, tags: ["keepme"])

        let onDisk = try await db.fetchFavoriteItems().first { $0.id == old.id }?.tags
        XCTAssertEqual(onDisk ?? [], ["keepme"], "removing a tag on an old favorite must persist")
    }

    /// A favorited screenshot must still receive its OCR text, or it is
    /// unsearchable forever.
    func testOCRWriteBackReachesAFavoriteOutsideTheWindow() async throws {
        let (store, db) = try await makeStore(limit: 5)
        let old = try await makeFavoriteOutsideWindow(store, db)

        await store.applyDetectedMetadata(id: old.id, tags: ["ocr"], embedding: nil)

        let onDisk = try await db.fetchFavoriteItems().first { $0.id == old.id }?.tags
        XCTAssertEqual(onDisk ?? [], ["ocr"], "OCR result for a favorited row outside the window was discarded")
    }

    /// The in-window path must keep working unchanged.
    func testAddingATagToAnItemInsideTheWindowStillWorks() async throws {
        let (store, db) = try await makeStore(limit: 50)
        let item = ClipboardItem(type: "text", content: "inside the window")
        try await db.insertClipboardItem(item)
        store.items = [item]

        await store.updateMetadata(id: item.id, tags: ["tagged"])

        XCTAssertEqual(store.items.first { $0.id == item.id }?.tags, ["tagged"])
        let onDisk = try await db.fetchAllClipboardItems().first { $0.id == item.id }?.tags
        XCTAssertEqual(onDisk ?? [], ["tagged"])
    }
}
