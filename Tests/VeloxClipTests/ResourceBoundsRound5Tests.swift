import XCTest
@testable import VeloxClip

/// Round-5 resource and ingestion findings.
@MainActor
final class ResourceBoundsRound5Tests: XCTestCase {

    // MARK: - Whitespace-only clips

    /// Double-clicking past the end of a line copies whitespace. That must not
    /// become a history row: it renders with no title at all, just
    /// "Plain Text · 0 chars", and it displaces a real entry.
    func testWhitespaceOnlyCopyIsNotIngested() {
        for blank in ["   \n\t  ", " ", "\n", "\t\t"] {
            let payload = PasteboardPayload(text: blank)
            let kind = IngestionPipeline.classify(payload)
            if case .none = kind { continue }
            XCTFail("whitespace-only copy became a history row: \(kind) for \(blank.debugDescription)")
        }
    }

    /// Text with real content around whitespace must still be ingested verbatim
    /// — trimming the stored content would corrupt indented code.
    func testRealTextIsStillIngestedWithItsWhitespaceIntact() {
        let indented = "    let x = 1\n    let y = 2\n"
        let kind = IngestionPipeline.classify(PasteboardPayload(text: indented))
        guard case .text(let stored) = kind else {
            return XCTFail("indented code must still be ingested as text, got \(kind)")
        }
        XCTAssertEqual(stored, indented, "stored content must keep its leading whitespace")
    }

    // MARK: - Cache byte bounds

    /// Both preview caches are keyed on the full document text and hold derived
    /// copies of it. Bounded at 100 entries, previewing 100 one-megabyte
    /// documents pinned hundreds of megabytes for the rest of the session.
    func testCacheEvictsOnBytesNotJustEntryCount() {
        var cache = FIFOCache<String, String>(maxEntries: 100, maxBytes: 4 * 1024 * 1024) { key, value in
            key.utf8.count + value.utf8.count
        }
        let oneMB = String(repeating: "x", count: 1024 * 1024)

        for i in 0..<20 {
            cache["doc-\(i)"] = oneMB
        }

        XCTAssertLessThanOrEqual(
            cache.byteCount, 4 * 1024 * 1024,
            "cache pinned \(cache.byteCount / 1024 / 1024) MB despite a 4 MB budget"
        )
        XCTAssertLessThan(cache.count, 20, "nothing was evicted; the byte budget is not enforced")
        XCTAssertNotNil(cache["doc-19"], "the most recent entry must survive eviction")
    }

    /// A single value larger than the whole budget must not wedge the cache.
    func testAnOversizedValueDoesNotWedgeTheCache() {
        var cache = FIFOCache<String, String>(maxEntries: 100, maxBytes: 1024) { key, value in
            key.utf8.count + value.utf8.count
        }
        cache["huge"] = String(repeating: "y", count: 8192)
        cache["small"] = "ok"

        XCTAssertEqual(cache["small"], "ok", "a normal entry must still be storable after an oversized one")
        XCTAssertLessThanOrEqual(cache.byteCount, 8192 + 1024, "the cache must not accumulate past its budget")
    }

    /// The entry-count bound must keep working for callers that do not set a
    /// byte budget.
    func testEntryCountBoundStillApplies() {
        var cache = FIFOCache<Int, Int>(maxEntries: 3)
        for i in 0..<10 { cache[i] = i }
        XCTAssertEqual(cache.count, 3)
        XCTAssertNil(cache[0], "the oldest entry must be evicted first")
        XCTAssertEqual(cache[9], 9)
    }

    /// The shipped preview caches must actually carry a byte budget.
    func testPreviewCachesDeclareAByteBudget() {
        MarkdownView.chunksCache.removeAll()
        JSONPreviewView.jsonCache.removeAll()
        XCTAssertGreaterThan(MarkdownView.chunksCache.byteLimit, 0,
                             "the markdown chunk cache must be bounded by bytes, not just entries")
        XCTAssertGreaterThan(JSONPreviewView.jsonCache.byteLimit, 0,
                             "the JSON preview cache must be bounded by bytes, not just entries")
    }
}
