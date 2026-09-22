import XCTest
@testable import VeloxClip

/// Probes the interaction between the bounded initial load and history trimming.
@MainActor
final class LoadLimitInteractionTests: XCTestCase {
    /// Lowering the history limit must eventually bring the stored row count
    /// down to it. With a bounded read, trimming only ever sees the loaded
    /// window — so rows beyond it can be stranded on disk.
    func testLoweringTheLimitTrimsEverythingOnDisk() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()

        // 60 rows on disk
        for i in 0..<60 {
            var item = ClipboardItem(type: "text", content: "item \(i)")
            item.createdAt = Date(timeIntervalSince1970: TimeInterval(1_000 + i))
            try await db.insertClipboardItem(item)
        }

        // User drops the limit to 10
        settings.historyLimit = 10

        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: true)
        try await TestSupport.waitUntil {
            await MainActor.run { !store.items.isEmpty }
        }
        // Let the trim's fire-and-forget delete land
        try await Task.sleep(nanoseconds: 300_000_000)

        let onDisk = try await db.fetchAllClipboardItems().count
        XCTAssertEqual(onDisk, 10,
                       "everything beyond the limit must be trimmed, not just what fit in the loaded window")
    }

    /// Favorites are exempt from the limit but still occupy slots in a bounded
    /// read. A user with many favorites must still see their recent history.
    func testManyFavoritesDoNotPushHistoryOutOfTheLoadedWindow() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        settings.historyLimit = 10   // loaded window would be 20 rows

        // 25 favorites, all older than the history below
        for i in 0..<25 {
            var fav = ClipboardItem(type: "text", content: "fav \(i)")
            fav.createdAt = Date(timeIntervalSince1970: TimeInterval(1_000 + i))
            fav.isFavorite = true
            fav.favoritedAt = fav.createdAt
            try await db.insertClipboardItem(fav)
        }
        // 5 recent normal items
        var recentIDs: [UUID] = []
        for i in 0..<5 {
            var item = ClipboardItem(type: "text", content: "recent \(i)")
            item.createdAt = Date(timeIntervalSince1970: TimeInterval(9_000 + i))
            recentIDs.append(item.id)
            try await db.insertClipboardItem(item)
        }

        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: true)
        try await TestSupport.waitUntil {
            await MainActor.run { !store.items.isEmpty }
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        let loadedRecent = store.items.filter { recentIDs.contains($0.id) }.count
        XCTAssertEqual(loadedRecent, 5,
                       "recent history must survive a window crowded with favorites")
    }
}
