import XCTest
@testable import VeloxClip

/// `items` is a bounded window; `favoriteItems` is not. Anything that assumes
/// `items` is the only source of truth breaks for favorites outside the window
/// — which, since favorites are exempt from the history limit, is a normal
/// steady state rather than a race.
@MainActor
final class FavoritesOutsideWindowTests: XCTestCase {
    private func makeStore(limit: Int) async throws -> (ClipboardStore, DatabaseManager, AppSettings) {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        settings.historyLimit = limit
        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: false)
        return (store, db, settings)
    }

    /// The star button in the Favorites tab must work on every favorite, not
    /// just the ones that happen to be inside the loaded window.
    func testUnfavoritingAFavoriteOutsideTheWindowUpdatesBothTheUIAndDisk() async throws {
        let (store, db, _) = try await makeStore(limit: 5)

        var old = ClipboardItem(type: "text", content: "an old favorite")
        old.createdAt = Date(timeIntervalSince1970: 100)
        old.isFavorite = true
        old.favoritedAt = old.createdAt
        try await db.insertClipboardItem(old)

        // Exactly the designed state: present in favoriteItems, absent from the
        // bounded items window.
        store.items = []
        store.favoriteItems = [old]

        let oldID = old.id
        store.toggleFavorite(for: old)

        XCTAssertFalse(store.favoriteItems.contains { $0.id == oldID },
                       "the row must leave the Favorites list immediately")

        try await TestSupport.waitUntil {
            let rows = try await db.fetchFavoriteItems()
            return !rows.contains { $0.id == oldID }
        }
        let onDisk = try await db.fetchFavoriteItems()
        XCTAssertFalse(onDisk.contains { $0.id == oldID }, "…and on disk")
    }

    /// Favoriting from the history list must still work when the row is in
    /// `items` — the common path, guarding against a regression in the fix.
    func testFavoritingAnItemInsideTheWindowStillWorks() async throws {
        let (store, db, _) = try await makeStore(limit: 5)

        let item = ClipboardItem(type: "text", content: "in the window")
        try await db.insertClipboardItem(item)
        store.items = [item]

        store.toggleFavorite(for: item)

        XCTAssertTrue(store.items.first?.isFavorite ?? false)
        XCTAssertTrue(store.favoriteItems.contains { $0.id == item.id })

        try await TestSupport.waitUntil {
            let rows = try await db.fetchFavoriteItems()
            return rows.contains { $0.id == item.id }
        }
    }

    /// markUsed keeps the favorites list in step for a row outside the window,
    /// so pasting an old favorite does not leave a stale copy on screen.
    func testMarkUsedUpdatesAFavoriteOutsideTheWindow() async throws {
        let (store, db, _) = try await makeStore(limit: 5)

        var old = ClipboardItem(type: "text", content: "old favorite")
        old.createdAt = Date(timeIntervalSince1970: 100)
        old.isFavorite = true
        old.favoritedAt = old.createdAt
        try await db.insertClipboardItem(old)

        store.items = []
        store.favoriteItems = [old]

        let oldID = old.id
        store.markUsed(oldID)

        try await TestSupport.waitUntil {
            let rows = try await db.fetchAllClipboardItems()
            return rows.first { $0.id == oldID }?.lastUsedAt != nil
        }
        let stored = try await db.fetchAllClipboardItems().first { $0.id == oldID }
        XCTAssertNotNil(stored?.lastUsedAt, "pasting an old favorite must record the use")
        XCTAssertEqual(stored?.createdAt.timeIntervalSince1970 ?? 0, 100, accuracy: 0.01,
                       "…without rewriting createdAt")
    }

    /// Clear History must not strand rows or leave ghosts, whichever way the
    /// in-memory and on-disk favorite flags disagree.
    func testClearHistoryLeavesNoGhostsAndStrandsNothing() async throws {
        let (store, db, _) = try await makeStore(limit: 50)

        let plain = ClipboardItem(type: "text", content: "plain")
        try await db.insertClipboardItem(plain)

        var starred = ClipboardItem(type: "text", content: "starred")
        starred.isFavorite = true
        starred.favoritedAt = Date()
        try await db.insertClipboardItem(starred)

        store.items = [starred, plain]
        store.favoriteItems = [starred]

        // Un-star immediately before clearing: the write is still in flight, so
        // memory says not-favorite while disk still says favorite.
        store.toggleFavorite(for: starred)
        await store.clearHistory()

        try await TestSupport.waitUntil {
            let rows = try await db.fetchAllClipboardItems()
            return rows.count <= 1
        }

        let onDisk = Set(try await db.fetchAllClipboardItems().map(\.id))
        let inMemory = Set(store.items.map(\.id)).union(store.favoriteItems.map(\.id))

        XCTAssertTrue(inMemory.isSubset(of: onDisk),
                      "no list may hold a row that is gone from disk")
        XCTAssertFalse(onDisk.contains(plain.id), "the plain row must be gone")
        XCTAssertFalse(onDisk.contains(starred.id),
                       "a row un-starred just before clearing must not survive it")
    }
}
