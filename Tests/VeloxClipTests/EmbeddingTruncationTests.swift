import XCTest
@testable import VeloxClip

/// `generateEmbedding` truncates to 500 characters and then uses the truncated
/// text as the cache key, while ingestion embeds anything up to 2000
/// characters. Two different long items that share an opening are therefore one
/// cache entry — and semantic search compares only their first 500 characters.
final class EmbeddingTruncationTests: XCTestCase {
    /// Documents the truncation boundary the two limits disagree on.
    func testIngestionEmbedsUpToFourTimesWhatIsActuallyEmbedded() {
        // ClipboardMonitor embeds text of 3...2000 characters
        let ingestUpperBound = 2000
        // AIService.generateEmbedding truncates to 500 before embedding
        let embeddedPrefix = 500
        XCTAssertGreaterThan(ingestUpperBound, embeddedPrefix,
                             "text between these bounds is only partially represented")
    }

    /// The consequence: two distinct documents sharing a 500-character opening
    /// produce the same cache key, so the second one gets the first one's
    /// vector — they become indistinguishable to semantic search.
    func testDocumentsSharingAnOpeningCollideOnTheCacheKey() async {
        let shared = String(repeating: "a", count: 500)
        let docA = shared + " the tail that makes this about databases"
        let docB = shared + " the tail that makes this about cooking"

        // Mirror what generateEmbedding does to build its key
        func cacheKey(_ text: String) -> String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.count > 500 ? String(normalized.prefix(500)) : normalized
        }

        XCTAssertEqual(cacheKey(docA), cacheKey(docB),
                       "distinct documents collapse to one cache entry")
        XCTAssertNotEqual(docA, docB, "…even though the documents differ")
    }

    /// Short text — the overwhelming majority of clipboard items — is unaffected.
    func testShortTextIsRepresentedInFull() {
        let text = "a normal snippet"
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = normalized.count > 500 ? String(normalized.prefix(500)) : normalized
        XCTAssertEqual(key, normalized)
    }
}
