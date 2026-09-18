import XCTest
@testable import VeloxClip

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testDeleteItemsUsesVisibleItemsInsteadOfBackingStoreOffsets() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let store = ClipboardStore(dbManager: databaseManager, settings: AppSettings(dbManager: databaseManager, autoLoad: false), shouldLoad: false)

        let first = ClipboardItem(type: "text", content: "first")
        let target = ClipboardItem(type: "text", content: "target")
        var favorite = ClipboardItem(type: "text", content: "favorite")
        favorite.isFavorite = true
        favorite.favoritedAt = Date()

        store.items = [first, target, favorite]
        store.favoriteItems = [favorite]

        try await databaseManager.insertClipboardItem(first)
        try await databaseManager.insertClipboardItem(target)
        try await databaseManager.insertClipboardItem(favorite)

        let visibleItems = [target]
        await store.deleteItems(at: IndexSet(integer: 0), in: visibleItems)

        let currentItemIDs = store.items.map { $0.id }
        let currentFavoriteIDs = store.favoriteItems.map { $0.id }

        XCTAssertEqual(currentItemIDs, [first.id, favorite.id])
        XCTAssertEqual(currentFavoriteIDs, [favorite.id])

        let persistedItems = try await databaseManager.fetchAllClipboardItems()
        XCTAssertEqual(Set(persistedItems.map { $0.id }), Set([first.id, favorite.id]))
    }

    func testUpdateMetadataPersistsTagsAndEmbedding() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let store = ClipboardStore(dbManager: databaseManager, settings: AppSettings(dbManager: databaseManager, autoLoad: false), shouldLoad: false)

        var item = ClipboardItem(type: "text", content: "semantic search text")
        item.tags = []

        store.items = [item]
        try await databaseManager.insertClipboardItem(item)

        let embedding = try JSONEncoder().encode([0.1, 0.2, 0.3])
        await store.updateMetadata(id: item.id, tags: ["URL", "Code"], embedding: embedding)

        let storedItem = store.items.first
        XCTAssertEqual(storedItem?.tags, ["URL", "Code"])
        XCTAssertEqual(storedItem?.embedding, embedding)

        let persistedItems = try await databaseManager.fetchAllClipboardItems()
        let persistedItem = persistedItems.first { $0.id == item.id }
        XCTAssertEqual(persistedItem?.tags, ["URL", "Code"])
        XCTAssertEqual(persistedItem?.embedding, embedding)
    }

    func testListFetchOmitsBlobButKeepsHash() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))

        let blob = Data([9, 9, 9])
        let item = ClipboardItem(type: "image", data: blob)
        try await databaseManager.insertClipboardItem(item)

        let fetched = try await databaseManager.fetchAllClipboardItems().first
        XCTAssertNil(fetched?.data)
        XCTAssertEqual(fetched?.dataHash, item.dataHash)

        let loadedBlob = try await databaseManager.fetchItemData(id: item.id)
        XCTAssertEqual(loadedBlob, blob)
    }

    func testAddItemDeduplicatesByDataHashAndPreservesCreatedAt() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let store = ClipboardStore(dbManager: databaseManager, settings: AppSettings(dbManager: databaseManager, autoLoad: false), shouldLoad: false)

        var original = ClipboardItem(type: "image", data: Data([1, 2, 3]))
        original.createdAt = Date(timeIntervalSinceNow: -3600)
        var strippedOriginal = original
        strippedOriginal.data = nil // mimic a lazily-loaded list item
        let other = ClipboardItem(type: "text", content: "unrelated")

        store.items = [other, strippedOriginal]

        let duplicate = ClipboardItem(type: "image", data: Data([1, 2, 3]))
        store.addItem(duplicate)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.id, original.id)
        XCTAssertEqual(store.items.first?.createdAt, original.createdAt)
        XCTAssertNotNil(store.items.first?.lastUsedAt)
    }

    func testMarkUsedMovesToTopWithoutRewritingCreatedAt() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let store = ClipboardStore(dbManager: databaseManager, settings: AppSettings(dbManager: databaseManager, autoLoad: false), shouldLoad: false)

        var older = ClipboardItem(type: "text", content: "older")
        older.createdAt = Date(timeIntervalSinceNow: -7200)
        let newer = ClipboardItem(type: "text", content: "newer")

        store.items = [newer, older]
        store.markUsed(older.id)

        XCTAssertEqual(store.items.first?.id, older.id)
        XCTAssertEqual(store.items.first?.createdAt, older.createdAt)
        XCTAssertNotNil(store.items.first?.lastUsedAt)
    }


    // MARK: History limit

    func testEnforceHistoryLimitTrimsOldestNonFavoritesOnly() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = try await makeLoadedSettings(dbManager: databaseManager, historyLimit: 2)
        let store = ClipboardStore(dbManager: databaseManager, settings: settings, shouldLoad: false)

        // Newest first, like the live list
        let newest = ClipboardItem(type: "text", content: "newest")
        let middle = ClipboardItem(type: "text", content: "middle")
        var favorite = ClipboardItem(type: "text", content: "favorite (old)")
        favorite.isFavorite = true
        let oldest = ClipboardItem(type: "text", content: "oldest")
        for item in [newest, middle, favorite, oldest] { try await databaseManager.insertClipboardItem(item) }
        store.items = [newest, middle, favorite, oldest]

        store.enforceHistoryLimit()

        XCTAssertEqual(store.items.map(\.id), [newest.id, middle.id, favorite.id])
        try await TestSupport.waitUntil { try await databaseManager.fetchAllClipboardItems().count == 3 }
        let persisted = try await databaseManager.fetchAllClipboardItems()
        XCTAssertEqual(Set(persisted.map(\.id)), Set([newest.id, middle.id, favorite.id]))
    }

    func testEnforceHistoryLimitIsNoOpWhenLimitIsNotPositive() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = try await makeLoadedSettings(dbManager: databaseManager, historyLimit: 100)
        settings.historyLimit = 0
        let store = ClipboardStore(dbManager: databaseManager, settings: settings, shouldLoad: false)
        store.items = (0..<3).map { ClipboardItem(type: "text", content: "\($0)") }

        store.enforceHistoryLimit()

        XCTAssertEqual(store.items.count, 3)
    }

    func testEnforceHistoryLimitWaitsForSettingsToLoad() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: databaseManager, autoLoad: false)
        settings.historyLimit = 1
        let store = ClipboardStore(dbManager: databaseManager, settings: settings, shouldLoad: false)
        store.items = (0..<3).map { ClipboardItem(type: "text", content: "\($0)") }

        store.enforceHistoryLimit()

        XCTAssertEqual(store.items.count, 3, "must not trim against an unloaded limit")
    }

    func testLoweringHistoryLimitInSettingsTrimsImmediately() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = try await makeLoadedSettings(dbManager: databaseManager, historyLimit: 10)
        let store = ClipboardStore(dbManager: databaseManager, settings: settings, shouldLoad: false)
        store.items = (0..<5).map { ClipboardItem(type: "text", content: "\($0)") }

        settings.historyLimit = 2

        XCTAssertEqual(store.items.count, 2)
    }

    // MARK: Clear history

    func testClearHistoryKeepsFavoritesInMemoryAndOnDisk() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let store = ClipboardStore(dbManager: databaseManager, settings: AppSettings(dbManager: databaseManager, autoLoad: false), shouldLoad: false)
        var favorite = ClipboardItem(type: "text", content: "keep")
        favorite.isFavorite = true
        let regular = ClipboardItem(type: "text", content: "drop")
        try await databaseManager.insertClipboardItem(favorite)
        try await databaseManager.insertClipboardItem(regular)
        store.items = [regular, favorite]
        store.favoriteItems = [favorite]

        await store.clearHistory()

        XCTAssertEqual(store.items.map(\.id), [favorite.id])
        let persisted = try await databaseManager.fetchAllClipboardItems()
        XCTAssertEqual(persisted.map(\.id), [favorite.id])
    }

    // MARK: Detected metadata

    func testApplyDetectedMetadataMergesWithUserTags() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let store = ClipboardStore(dbManager: databaseManager, settings: AppSettings(dbManager: databaseManager, autoLoad: false), shouldLoad: false)
        var item = ClipboardItem(type: "text", content: "https://example.com")
        item.tags = ["todo"]
        try await databaseManager.insertClipboardItem(item)
        store.items = [item]

        await store.applyDetectedMetadata(id: item.id, tags: ["URL"], embedding: Data([1]))

        XCTAssertEqual(store.items.first?.tags, ["todo", "URL"])
        let persisted = try await databaseManager.fetchAllClipboardItems().first
        XCTAssertEqual(persisted?.tags, ["todo", "URL"])
        XCTAssertEqual(persisted?.embedding, Data([1]))
    }

    func testApplyDetectedMetadataDoesNotClobberFavoriteToggledMeanwhile() async throws {
        let databaseManager = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let store = ClipboardStore(dbManager: databaseManager, settings: AppSettings(dbManager: databaseManager, autoLoad: false), shouldLoad: false)
        let item = ClipboardItem(type: "text", content: "starred later")
        try await databaseManager.insertClipboardItem(item)
        store.items = [item] // in-memory snapshot still says isFavorite == false

        try await databaseManager.toggleFavorite(id: item.id)
        await store.applyDetectedMetadata(id: item.id, tags: ["URL"], embedding: nil)

        let persisted = try await databaseManager.fetchAllClipboardItems().first
        XCTAssertEqual(persisted?.isFavorite, true)
    }

    // MARK: Helpers

    private func makeLoadedSettings(dbManager: DatabaseManager, historyLimit: Int) async throws -> AppSettings {
        try await dbManager.setSetting(key: "historyLimit", value: String(historyLimit))
        let settings = AppSettings(dbManager: dbManager, autoLoad: false)
        await settings.load()
        return settings
    }

}
