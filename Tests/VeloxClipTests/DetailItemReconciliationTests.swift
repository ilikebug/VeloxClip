import XCTest
@testable import VeloxClip

/// The detail pane keeps a debounced snapshot (it carries the lazily-loaded
/// blob) while the store holds the live row. Rendering a mix of the two meant
/// background updates — OCR being the visible one — never reached the parts of
/// the pane that read the snapshot.
final class DetailItemReconciliationTests: XCTestCase {
    private func imageItem(content: String? = nil, blob: Data? = Data([1, 2, 3])) -> ClipboardItem {
        var item = ClipboardItem(type: "image", data: blob)
        item.content = content
        return item
    }

    /// The bug: OCR finishes while the pane is open, the store row gains the
    /// recognised text, but the snapshot the OCR panel reads never saw it.
    func testOCRTextFromTheStoreReachesTheRenderedItem() {
        var snapshot = imageItem(content: nil)
        var live = snapshot
        live.data = nil                    // list rows never carry the blob
        live.content = "recognised text"
        live.tags = ["OCR"]

        let merged = DetailItemReconciliation.merge(snapshot: snapshot, live: live)

        XCTAssertEqual(merged.content, "recognised text", "OCR text must reach the pane without reselecting")
        XCTAssertEqual(merged.tags, ["OCR"])
        snapshot.content = nil // silence unused-mutation warning intent
    }

    /// The whole reason the snapshot exists: it holds the blob that list rows
    /// omit. A merge that takes the live row wholesale would blank the image.
    func testMergeKeepsTheLoadedBlobThatTheStoreDoesNotHave() {
        let snapshot = imageItem(blob: Data([9, 9, 9]))
        var live = snapshot
        live.data = nil
        live.content = "ocr"

        let merged = DetailItemReconciliation.merge(snapshot: snapshot, live: live)

        XCTAssertEqual(merged.data, Data([9, 9, 9]), "the lazily-loaded blob must survive the merge")
    }

    func testFavoriteAndTagEditsFromTheStoreAreReflected() {
        let snapshot = imageItem(content: "x")
        var live = snapshot
        live.data = nil
        live.isFavorite = true
        live.favoritedAt = Date(timeIntervalSince1970: 1_000)
        live.tags = ["a", "b"]

        let merged = DetailItemReconciliation.merge(snapshot: snapshot, live: live)

        XCTAssertEqual(merged.isFavorite, true)
        XCTAssertEqual(merged.favoritedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(merged.tags, ["a", "b"])
    }

    /// A different row must never be merged in — that would render one item's
    /// blob under another item's text.
    func testMergeIgnoresADifferentItem() {
        let snapshot = imageItem(content: "mine", blob: Data([1]))
        var other = imageItem(content: "theirs", blob: nil)
        other.tags = ["wrong"]

        let merged = DetailItemReconciliation.merge(snapshot: snapshot, live: other)

        XCTAssertEqual(merged.content, "mine", "a different row must not overwrite the snapshot")
        XCTAssertEqual(merged.data, Data([1]))
    }

    func testMergeWithNoLiveRowReturnsTheSnapshot() {
        let snapshot = imageItem(content: "only copy", blob: Data([5]))
        let merged = DetailItemReconciliation.merge(snapshot: snapshot, live: nil)
        XCTAssertEqual(merged.content, "only copy")
        XCTAssertEqual(merged.data, Data([5]))
    }

    /// End-to-end through the real store: the pane holds a blob-carrying
    /// snapshot, OCR writes back the way ClipboardMonitor does, and the merged
    /// item the pane renders must show the text while keeping the image.
    @MainActor
    func testOCRWriteBackThroughTheRealStoreReachesThePane() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: false)

        let png = TestSupport.makePNG(width: 4, height: 4)
        let stored = ClipboardItem(type: "image", data: png)
        try await db.insertClipboardItem(stored)

        // The list row the store holds: no blob, no OCR text yet
        var listRow = stored
        listRow.data = nil
        store.items = [listRow]

        // The pane's snapshot: same row, blob resolved via loadData(for:)
        var snapshot = listRow
        snapshot.data = png

        // Nothing to show before OCR lands
        let before = DetailItemReconciliation.merge(
            snapshot: snapshot,
            live: store.items.first { $0.id == stored.id }
        )
        XCTAssertNil(before.content)

        // Exactly what ClipboardMonitor does when Vision finishes
        store.updateItem(id: stored.id, content: "text from the screenshot")

        let after = DetailItemReconciliation.merge(
            snapshot: snapshot,
            live: store.items.first { $0.id == stored.id }
        )
        XCTAssertEqual(after.content, "text from the screenshot",
                       "the OCR panel must appear without reselecting the item")
        XCTAssertTrue(after.tags.contains("OCR"))
        XCTAssertEqual(after.data, png, "and the image must still render")
    }

    /// If the live row does carry a blob (a freshly ingested item still holds
    /// its data in memory), prefer it — it is at least as fresh.
    func testLiveBlobWinsWhenPresent() {
        let snapshot = imageItem(blob: Data([1]))
        var live = snapshot
        live.data = Data([2])

        let merged = DetailItemReconciliation.merge(snapshot: snapshot, live: live)
        XCTAssertEqual(merged.data, Data([2]))
    }
}
