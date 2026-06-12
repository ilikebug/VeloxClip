import XCTest
@testable import VeloxClip

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testDeleteItemsUsesVisibleItemsInsteadOfBackingStoreOffsets() async throws {
        let databaseManager = DatabaseManager(databaseURL: makeDatabaseURL(directoryName: #function))
        let store = ClipboardStore(dbManager: databaseManager, shouldLoad: false)

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
        let databaseManager = DatabaseManager(databaseURL: makeDatabaseURL(directoryName: #function))
        let store = ClipboardStore(dbManager: databaseManager, shouldLoad: false)

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

    func testUpdateWithNilDataPreservesStoredBlob() async throws {
        let databaseManager = DatabaseManager(databaseURL: makeDatabaseURL(directoryName: #function))

        let blob = Data([1, 2, 3, 4])
        var item = ClipboardItem(type: "image", data: blob)
        try await databaseManager.insertClipboardItem(item)

        // Simulate a lazily-loaded item (no blob in memory) getting a metadata update
        item.data = nil
        item.tags = ["OCR"]
        try await databaseManager.updateClipboardItem(item)

        let storedBlob = try await databaseManager.fetchItemData(id: item.id)
        XCTAssertEqual(storedBlob, blob)
    }

    func testListFetchOmitsBlobButKeepsHash() async throws {
        let databaseManager = DatabaseManager(databaseURL: makeDatabaseURL(directoryName: #function))

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
        let databaseManager = DatabaseManager(databaseURL: makeDatabaseURL(directoryName: #function))
        let store = ClipboardStore(dbManager: databaseManager, shouldLoad: false)

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
        let databaseManager = DatabaseManager(databaseURL: makeDatabaseURL(directoryName: #function))
        let store = ClipboardStore(dbManager: databaseManager, shouldLoad: false)

        var older = ClipboardItem(type: "text", content: "older")
        older.createdAt = Date(timeIntervalSinceNow: -7200)
        let newer = ClipboardItem(type: "text", content: "newer")

        store.items = [newer, older]
        store.markUsed(older.id)

        XCTAssertEqual(store.items.first?.id, older.id)
        XCTAssertEqual(store.items.first?.createdAt, older.createdAt)
        XCTAssertNotNil(store.items.first?.lastUsedAt)
    }

    private func makeDatabaseURL(directoryName: String) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root.appendingPathComponent("VeloxClipTests-\(directoryName)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("veloxclip.db")
    }
}
