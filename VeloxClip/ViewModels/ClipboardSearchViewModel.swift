import Foundation
import Combine

/// The hybrid search pipeline, extracted from `MainView`.
///
/// It lived inline in a 773-line view, so none of the ranking rules — the 0.9
/// keyword weight, the score merge, the favorite/recency tie-break — could be
/// tested. The embedding source and similarity function are injected so ranking
/// is exercisable without a live `AIService`.
@MainActor
final class ClipboardSearchViewModel: ObservableObject {
    @Published private(set) var results: [ClipboardItem] = []
    @Published private(set) var isSearching = false

    /// Keyword hits get this base score; semantic similarity has to beat it to
    /// outrank an exact match.
    nonisolated static let keywordScore = 0.9
    /// Below this similarity a semantic hit is noise.
    nonisolated static let semanticThreshold = 0.5
    nonisolated static let maxSemanticResults = 20
    /// Keyword results publish immediately; the semantic pass waits this long
    /// so it doesn't run on every keystroke.
    nonisolated static let semanticDebounce: Duration = .milliseconds(300)
    /// Single-character queries match too much to be worth embedding.
    nonisolated static let minimumSemanticQueryLength = 2

    private var searchTask: Task<Void, Never>?
    private var cachedSemanticResults = FIFOCache<String, [(UUID, Double)]>(maxEntries: 50)

    private let loadEmbeddings: @Sendable ([UUID]) async -> [UUID: Data]
    private let embedQuery: @Sendable (String) async -> [Double]?
    private let similarity: @Sendable ([Double], [Double]) -> Double
    private let debounce: Duration

    nonisolated init(
        loadEmbeddings: @escaping @Sendable ([UUID]) async -> [UUID: Data] = { ids in
            (try? await DatabaseManager.shared.fetchEmbeddings(ids: ids)) ?? [:]
        },
        embedQuery: @escaping @Sendable (String) async -> [Double]? = { query in
            await AIService.shared.generateEmbedding(for: query)
        },
        similarity: @escaping @Sendable ([Double], [Double]) -> Double = { lhs, rhs in
            AIService.shared.calculateSimilarity(lhs, rhs)
        },
        debounce: Duration = ClipboardSearchViewModel.semanticDebounce
    ) {
        self.loadEmbeddings = loadEmbeddings
        self.embedQuery = embedQuery
        self.similarity = similarity
        self.debounce = debounce
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
    }

    func clear() {
        cancel()
        results = []
        isSearching = false
    }

    /// Runs the keyword pass immediately, then the debounced semantic pass,
    /// publishing after each. `onPublish` lets the view re-sync its selection.
    func search(query rawQuery: String,
                in baseItems: [ClipboardItem],
                onPublish: @escaping ([ClipboardItem]) -> Void) {
        cancel()

        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task { [weak self] in
            guard let self else { return }

            // 1. Keyword search: runs immediately (no debounce) and off the main thread
            let keywordMatches = await Task.detached(priority: .userInitiated) {
                Self.keywordMatches(query: query, in: baseItems)
            }.value

            if Task.isCancelled { return }

            var itemScores: [UUID: Double] = [:]
            for item in keywordMatches {
                itemScores[item.id] = Self.keywordScore
            }
            self.publish(itemScores, baseItems: baseItems, onPublish: onPublish)

            // 2. Semantic search: debounced, merged into the keyword results
            guard query.count >= Self.minimumSemanticQueryLength else {
                self.isSearching = false
                return
            }

            try? await Task.sleep(for: self.debounce)
            if Task.isCancelled { return }

            let semanticResults = await self.semanticMatches(query: query, in: baseItems)
            if Task.isCancelled { return }

            for (itemID, score) in semanticResults {
                itemScores[itemID] = max(itemScores[itemID] ?? 0, score)
            }
            self.publish(itemScores, baseItems: baseItems, onPublish: onPublish)
            self.isSearching = false
        }
    }

    // MARK: - Pure ranking

    nonisolated static func keywordMatches(query: String, in items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter { item in
            item.content?.localizedCaseInsensitiveContains(query) ?? false ||
            item.type.localizedCaseInsensitiveContains(query) ||
            (item.sourceApp?.localizedCaseInsensitiveContains(query) ?? false) ||
            item.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    /// Highest score first. Near-ties fall back to favorites, then to the same
    /// recency rule the history list uses (`lastUsedAt ?? createdAt`).
    nonisolated static func rank(_ itemScores: [UUID: Double], baseItems: [ClipboardItem]) -> [ClipboardItem] {
        let matchIDs = Set(itemScores.keys)
        return baseItems
            .filter { matchIDs.contains($0.id) }
            .map { ($0, itemScores[$0.id] ?? 0) }
            .sorted { lhs, rhs in
                if abs(lhs.1 - rhs.1) < 0.001 {
                    if lhs.0.isFavorite != rhs.0.isFavorite {
                        return lhs.0.isFavorite
                    }
                    return (lhs.0.lastUsedAt ?? lhs.0.createdAt) > (rhs.0.lastUsedAt ?? rhs.0.createdAt)
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    // MARK: - Private

    private func publish(_ itemScores: [UUID: Double],
                         baseItems: [ClipboardItem],
                         onPublish: ([ClipboardItem]) -> Void) {
        let ranked = Self.rank(itemScores, baseItems: baseItems)
        results = ranked
        onPublish(ranked)
    }

    private func semanticMatches(query: String, in baseItems: [ClipboardItem]) async -> [(UUID, Double)] {
        // Key on the candidate set as well as the query. Keying on the query
        // alone meant a repeated search returned its first run's hit list, so
        // anything copied since was invisible to semantic search for the rest
        // of the session — while keyword hits still appeared, which made the
        // gap look arbitrary rather than broken.
        let cacheKey = "\(query.lowercased())|\(baseItems.count)|\(baseItems.first?.id.uuidString ?? "")"
        if let cached = cachedSemanticResults[cacheKey] {
            return cached
        }

        // Vectors are no longer carried on list rows (they were tens of MB of
        // permanently-resident blobs the list never renders). Load just the ones
        // this search needs.
        let candidateIDs = baseItems.filter { $0.content != nil }.map(\.id)
        let vectors = await loadEmbeddings(candidateIDs)
        guard !vectors.isEmpty else { return [] }

        guard let queryVector = await embedQuery(query) else { return [] }

        // Decode each stored vector exactly once per item
        let similarity = self.similarity
        let scored = vectors.compactMap { itemID, blob -> (UUID, Double)? in
            guard let itemVector = ClipboardItem.decodeVector(blob) else { return nil }
            let score = similarity(queryVector, itemVector)
            return score >= Self.semanticThreshold ? (itemID, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(Self.maxSemanticResults)

        let finalResults = Array(scored)
        cachedSemanticResults[cacheKey] = finalResults
        return finalResults
    }
}
