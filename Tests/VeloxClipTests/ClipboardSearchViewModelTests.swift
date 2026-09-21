import XCTest
@testable import VeloxClip

@MainActor
final class ClipboardSearchViewModelTests: XCTestCase {
    private func item(_ content: String,
                      type: String = "text",
                      tags: [String] = [],
                      sourceApp: String? = nil,
                      favorite: Bool = false,
                      lastUsed: Date? = nil) -> ClipboardItem {
        var i = ClipboardItem(type: type, content: content, sourceApp: sourceApp)
        i.tags = tags
        i.isFavorite = favorite
        i.lastUsedAt = lastUsed
        return i
    }

    // MARK: - Keyword matching

    func testKeywordMatchesContentTypeSourceAppAndTags() {
        let items = [
            item("hello world"),
            item("nothing", type: "image"),
            item("nothing", sourceApp: "Xcode"),
            item("nothing", tags: ["Recipe"]),
            item("unrelated"),
        ]

        XCTAssertEqual(ClipboardSearchViewModel.keywordMatches(query: "hello", in: items).count, 1)
        XCTAssertEqual(ClipboardSearchViewModel.keywordMatches(query: "image", in: items).count, 1)
        XCTAssertEqual(ClipboardSearchViewModel.keywordMatches(query: "xcode", in: items).count, 1,
                       "source app match must be case-insensitive")
        XCTAssertEqual(ClipboardSearchViewModel.keywordMatches(query: "recipe", in: items).count, 1,
                       "tag match must be case-insensitive")
    }

    // MARK: - Ranking

    func testHigherScoreRanksFirst() {
        let a = item("a"), b = item("b"), c = item("c")
        let ranked = ClipboardSearchViewModel.rank(
            [a.id: 0.5, b.id: 0.95, c.id: 0.7],
            baseItems: [a, b, c]
        )
        XCTAssertEqual(ranked.map(\.id), [b.id, c.id, a.id])
    }

    /// A semantic hit must clear the 0.9 keyword weight to outrank an exact
    /// keyword match — that weighting is the whole point of the hybrid search.
    func testSemanticHitMustBeatTheKeywordWeightToOutrankIt() {
        let keyword = item("exact")
        let semantic = item("related")

        let weaker = ClipboardSearchViewModel.rank(
            [keyword.id: ClipboardSearchViewModel.keywordScore, semantic.id: 0.85],
            baseItems: [keyword, semantic]
        )
        XCTAssertEqual(weaker.first?.id, keyword.id)

        let stronger = ClipboardSearchViewModel.rank(
            [keyword.id: ClipboardSearchViewModel.keywordScore, semantic.id: 0.97],
            baseItems: [keyword, semantic]
        )
        XCTAssertEqual(stronger.first?.id, semantic.id)
    }

    func testNearTiesPreferFavorites() {
        let plain = item("one")
        let fav = item("two", favorite: true)
        let ranked = ClipboardSearchViewModel.rank(
            [plain.id: 0.9, fav.id: 0.9],
            baseItems: [plain, fav]
        )
        XCTAssertEqual(ranked.first?.id, fav.id, "equal scores must prefer a favorite")
    }

    /// Same recency rule the history list uses: lastUsedAt falling back to
    /// createdAt, never createdAt alone.
    func testNearTiesFallBackToRecencyUsingLastUsedAt() {
        let older = item("older", lastUsed: Date(timeIntervalSince1970: 1_000))
        let newer = item("newer", lastUsed: Date(timeIntervalSince1970: 2_000))
        let ranked = ClipboardSearchViewModel.rank(
            [older.id: 0.9, newer.id: 0.9],
            baseItems: [older, newer]
        )
        XCTAssertEqual(ranked.map(\.id), [newer.id, older.id])
    }

    func testScoresWithinTheTieThresholdAreTreatedAsEqual() {
        let fav = item("fav", favorite: true)
        let plain = item("plain")
        // 0.0005 apart — inside the 0.001 tie window, so the favorite wins
        let ranked = ClipboardSearchViewModel.rank(
            [fav.id: 0.9, plain.id: 0.9005],
            baseItems: [fav, plain]
        )
        XCTAssertEqual(ranked.first?.id, fav.id)
    }

    func testRankIgnoresItemsWithoutAScore() {
        let scored = item("scored"), unscored = item("unscored")
        let ranked = ClipboardSearchViewModel.rank([scored.id: 0.9], baseItems: [scored, unscored])
        XCTAssertEqual(ranked.map(\.id), [scored.id])
    }

    // MARK: - Pipeline

    func testKeywordResultsPublishBeforeTheSemanticPass() async throws {
        let hit = item("swift concurrency")
        let miss = item("groceries")

        let model = ClipboardSearchViewModel(
            loadEmbeddings: { _ in [:] },
            embedQuery: { _ in nil },
            similarity: { _, _ in 0 },
            debounce: .milliseconds(1)
        )

        model.search(query: "swift", in: [hit, miss]) { _ in }
        try await TestSupport.waitUntil {
            await MainActor.run { !model.results.isEmpty }
        }

        XCTAssertEqual(model.results.map(\.id), [hit.id])
    }

    func testSemanticResultsMergeIntoKeywordResults() async throws {
        let keywordHit = item("swift")
        var semanticOnly = item("concurrency primer")
        semanticOnly.lastUsedAt = Date()

        let vectors: [UUID: Data] = [
            semanticOnly.id: try JSONEncoder().encode([1.0, 0.0])
        ]

        let model = ClipboardSearchViewModel(
            loadEmbeddings: { _ in vectors },
            embedQuery: { _ in [1.0, 0.0] },
            similarity: { _, _ in 0.99 },
            debounce: .milliseconds(1)
        )

        model.search(query: "swift", in: [keywordHit, semanticOnly]) { _ in }
        try await TestSupport.waitUntil {
            await MainActor.run { model.results.count == 2 }
        }

        // 0.99 semantic beats the 0.9 keyword weight
        XCTAssertEqual(model.results.map(\.id), [semanticOnly.id, keywordHit.id])
    }

    func testEmptyQueryClearsResults() async throws {
        let model = ClipboardSearchViewModel(
            loadEmbeddings: { _ in [:] },
            embedQuery: { _ in nil },
            similarity: { _, _ in 0 },
            debounce: .milliseconds(1)
        )
        let only = item("something")

        model.search(query: "some", in: [only]) { _ in }
        try await TestSupport.waitUntil {
            await MainActor.run { !model.results.isEmpty }
        }

        model.search(query: "   ", in: [only]) { _ in }
        XCTAssertTrue(model.results.isEmpty, "a whitespace-only query must clear results")
        XCTAssertFalse(model.isSearching)
    }

    func testSingleCharacterQuerySkipsTheSemanticPass() async throws {
        actor CallCounter {
            private(set) var count = 0
            func record() { count += 1 }
        }
        let counter = CallCounter()

        let model = ClipboardSearchViewModel(
            loadEmbeddings: { _ in [:] },
            embedQuery: { _ in await counter.record(); return nil },
            similarity: { _, _ in 0 },
            debounce: .milliseconds(1)
        )
        let only = item("s")

        model.search(query: "s", in: [only]) { _ in }
        try await TestSupport.waitUntil {
            await MainActor.run { !model.isSearching }
        }

        let calls = await counter.count
        XCTAssertEqual(calls, 0, "a 1-character query matches too much to be worth embedding")
    }
}
