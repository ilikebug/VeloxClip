import XCTest
@testable import VeloxClip

/// Semantic results were cached on the lowercased query alone. A repeated
/// search replayed its first run's hit list, so anything copied since was
/// invisible to the semantic pass for the rest of the session (the cache holds
/// 50 entries). Keyword hits still appeared, which made the gap look arbitrary
/// rather than broken.
@MainActor
final class SemanticSearchCacheTests: XCTestCase {

    private func makeViewModel(embeddingFor: @escaping @Sendable (UUID) -> [Double])
        -> ClipboardSearchViewModel {
        ClipboardSearchViewModel(
            loadEmbeddings: { ids in
                var out: [UUID: Data] = [:]
                for id in ids {
                    let vector = embeddingFor(id)
                    out[id] = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                }
                return out
            },
            embedQuery: { _ in [1.0, 0.0] },
            similarity: { lhs, rhs in
                guard lhs.count == rhs.count else { return 0 }
                return zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
            },
            debounce: .milliseconds(1)
        )
    }

    /// Runs a search and settles, leaving `viewModel.results` from the final
    /// (semantic) publish.
    private func runSearch(_ viewModel: ClipboardSearchViewModel,
                           query: String,
                           items: [ClipboardItem]) async throws {
        viewModel.search(query: query, in: items) { _ in }
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    /// The same query run twice must see an item copied in between.
    func testARepeatedQuerySeesANewlyCopiedItem() async throws {
        // No literal overlap with the query, so ONLY the semantic pass can
        // surface these — otherwise the keyword pass masks the bug.
        let older = ClipboardItem(type: "text", content: "quarterly figures")
        let newer = ClipboardItem(type: "text", content: "annual figures")

        let viewModel = makeViewModel(embeddingFor: { _ in [1.0, 0.0] })

        try await runSearch(viewModel, query: "revenue", items: [older])
        let firstRun = viewModel.results
        XCTAssertTrue(firstRun.contains { $0.id == older.id },
                      "precondition: the semantic pass finds the original item")

        // The user copies something new, then repeats the same search
        try await runSearch(viewModel, query: "revenue", items: [newer, older])

        let results = viewModel.results
        XCTAssertTrue(results.contains { $0.id == newer.id },
                      "the newly copied item must be searchable, got \(results.map(\.content))")
    }

    /// Cache hits must still work when nothing changed — the cache has a job.
    func testTheCacheStillServesAnUnchangedCandidateSet() async throws {
        let counter = CallCounter()
        let item = ClipboardItem(type: "text", content: "invoice")
        let viewModel = ClipboardSearchViewModel(
            loadEmbeddings: { ids in
                await counter.increment()
                var out: [UUID: Data] = [:]
                for id in ids {
                    out[id] = [1.0, 0.0].withUnsafeBufferPointer { Data(buffer: $0) }
                }
                return out
            },
            embedQuery: { _ in [1.0, 0.0] },
            similarity: { lhs, rhs in zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 } },
            debounce: .milliseconds(1)
        )

        try await runSearch(viewModel, query: "invoice", items: [item])
        let afterFirst = await counter.value

        try await runSearch(viewModel, query: "invoice", items: [item])

        let afterSecond = await counter.value
        XCTAssertEqual(afterSecond, afterFirst,
                       "an unchanged candidate set must still hit the cache")
    }
}

/// Sendable counter for the cache-hit assertion.
private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
