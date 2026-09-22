import XCTest
@testable import VeloxClip

/// `generateEmbedding` used to truncate to 500 characters and then use the
/// truncated text as its cache key, while ingestion embeds up to 2000. Items
/// between the two bounds were half-represented in semantic search, and two
/// documents sharing a 500-character opening collapsed to one cache entry —
/// the second silently got the first one's vector.
final class EmbeddingTruncationTests: XCTestCase {
    /// The cache key must distinguish documents that share an opening.
    func testDocumentsSharingAnOpeningGetDistinctCacheKeys() {
        let shared = String(repeating: "a", count: 600)
        let docA = shared + " the tail that makes this about databases"
        let docB = shared + " the tail that makes this about cooking"

        XCTAssertNotEqual(AIService.cacheKey(for: docA), AIService.cacheKey(for: docB),
                          "distinct documents must not collapse to one cache entry")
    }

    /// Identical text must still hit the cache — that is the whole point of it.
    func testIdenticalTextSharesACacheKey() {
        XCTAssertEqual(AIService.cacheKey(for: "  A Snippet With Spacing  "),
                       AIService.cacheKey(for: "a snippet with spacing"),
                       "the key normalizes case and surrounding whitespace")
    }

    /// The embed window must cover everything ingestion is willing to embed,
    /// or items in the gap are only partially searchable.
    func testTheEmbedWindowCoversEverythingIngestionEmbeds() {
        XCTAssertGreaterThanOrEqual(AIService.maxEmbeddingLength,
                                    ClipboardIngestion.maxEmbeddableLength,
                                    "text ingestion embeds must be embedded in full")
    }

    /// A document inside the ingestion bound is represented in full, not by a
    /// prefix of it.
    func testTextWithinTheIngestionBoundIsEmbeddedWhole() {
        let text = String(repeating: "b", count: ClipboardIngestion.maxEmbeddableLength)
        XCTAssertEqual(AIService.textToEmbed(for: text).count, text.count,
                       "nothing within the ingestion bound may be truncated")
    }

    /// Beyond the bound a prefix is still better than nothing, but it must stay
    /// bounded so a pathological paste cannot stall the embedder.
    func testUnreasonablyLongTextIsStillBounded() {
        let huge = String(repeating: "c", count: AIService.maxEmbeddingLength * 4)
        XCTAssertEqual(AIService.textToEmbed(for: huge).count, AIService.maxEmbeddingLength)
    }

    func testEmptyTextHasNoEmbedding() async {
        let vector = await AIService.shared.generateEmbedding(for: "   \n  ")
        XCTAssertNil(vector)
    }
}
