import SwiftUI
import SwiftData

enum ViewMode {
    case favorites
    case history
}

struct MainView: View {
    @ObservedObject var store = ClipboardStore.shared
    @State private var selectedItem: ClipboardItem?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var viewMode: ViewMode = .history
    @State private var searchResults: [ClipboardItem] = []
    @State private var isSearching = false
    @State private var scrollTarget: UUID?
    
    // Debounced search text for semantic search
    @State private var searchTask: Task<Void, Never>?
    
    // Cached semantic search results - only store IDs and scores to save memory
    @State private var cachedSemanticResults = FIFOCache<String, [(UUID, Double)]>(maxEntries: 50)
    
    var displayItems: [ClipboardItem] {
        if searchText.isEmpty {
            return viewMode == .favorites ? store.favoriteItems : store.items
        }
        return searchResults
    }
    
    private func updateSearchResults() {
        searchTask?.cancel()
        
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let mode = viewMode
        
        if query.isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        let baseItems = mode == .favorites ? store.favoriteItems : store.items

        searchTask = Task {
            // 1. Keyword search: runs immediately (no debounce) and off the main thread
            let keywordMatches = await Task.detached(priority: .userInitiated) {
                baseItems.filter { item in
                    item.content?.localizedCaseInsensitiveContains(query) ?? false ||
                    item.type.localizedCaseInsensitiveContains(query) ||
                    (item.sourceApp?.localizedCaseInsensitiveContains(query) ?? false) ||
                    item.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                }
            }.value

            if Task.isCancelled { return }

            // Keyword matches get a high base score; publish right away
            var itemScores: [UUID: Double] = [:]
            for item in keywordMatches {
                itemScores[item.id] = 0.9
            }
            publishSearchResults(itemScores, baseItems: baseItems)

            // 2. Semantic search: debounced 300ms, merged into the keyword results
            guard query.count >= 2 else {
                isSearching = false
                return
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            let semanticResults = await performSemanticSearchAsync(query: query, baseItems: baseItems)
            if Task.isCancelled { return }

            for (itemId, similarity) in semanticResults {
                let currentScore = itemScores[itemId] ?? 0
                itemScores[itemId] = max(currentScore, similarity)
            }
            publishSearchResults(itemScores, baseItems: baseItems)
            isSearching = false
        }
    }

    private func publishSearchResults(_ itemScores: [UUID: Double], baseItems: [ClipboardItem]) {
        let allMatchIds = Set(itemScores.keys)
        let matchedItems = baseItems.filter { allMatchIds.contains($0.id) }

        let sortedResults = matchedItems.map { ($0, itemScores[$0.id] ?? 0) }
            .sorted { r1, r2 in
                if abs(r1.1 - r2.1) < 0.001 {
                    // If scores are very close, prioritize favorites then most recently used —
                    // same ordering the history list uses (lastUsedAt ?? createdAt)
                    if r1.0.isFavorite != r2.0.isFavorite {
                        return r1.0.isFavorite
                    }
                    return (r1.0.lastUsedAt ?? r1.0.createdAt) > (r2.0.lastUsedAt ?? r2.0.createdAt)
                }
                return r1.1 > r2.1
            }

        let finalItems = sortedResults.map { $0.0 }
        searchResults = finalItems

        // Select first item if search results changed
        if selectedItem == nil || !finalItems.contains(where: { $0.id == selectedItem?.id }) {
            selectedItem = finalItems.first
            scrollTarget = finalItems.first?.id
        }
    }

    private func performSemanticSearchAsync(query: String, baseItems: [ClipboardItem]) async -> [(UUID, Double)] {
        let normalizedQuery = query.lowercased()

        // Cache check
        if let cached = cachedSemanticResults[normalizedQuery] {
            return cached
        }

        let finalResults = await Task.detached(priority: .userInitiated) { () -> [(UUID, Double)] in
            guard let queryVector = await AIService.shared.generateEmbedding(for: query) else {
                return []
            }

            let threshold = 0.5
            let maxResults = 20

            // Decode each stored vector exactly once per item
            let results = baseItems.compactMap { item -> (UUID, Double)? in
                guard item.content != nil, let itemVector = item.vector else { return nil }
                let similarity = AIService.shared.calculateSimilarity(queryVector, itemVector)
                return similarity >= threshold ? (item.id, similarity) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxResults)

            return Array(results)
        }.value

        cachedSemanticResults[normalizedQuery] = finalResults

        return finalResults
    }

    
    var body: some View {
        VStack(spacing: 0) {
            // Top: Full-width Search Bar (Spotlight Style)
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DesignSystem.primaryGradient)
                
                TextField("Search anything in your clipboard history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelection()
                    }
                
                Spacer()
                
                // Favorite toggle button
                favoriteToggleButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(DesignSystem.backgroundBlur)
            .onKeyPress(.upArrow) {
                moveSelection(direction: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(direction: 1)
                return .handled
            }
            .onKeyPress(.return) {
                executeSelection()
                return .handled
            }
            .onKeyPress(.tab) {
                if isSearchFocused {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = viewMode == .history ? .favorites : .history
                    }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                WindowManager.shared.toggleWindow()
                return .handled
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Bottom Content: List and Preview
            HStack(spacing: 0) {
                // Left: Clipboard List (History)
                VStack(spacing: 0) {
                    ClipboardListView(selectedItem: $selectedItem, items: displayItems, scrollTarget: $scrollTarget)
                }
                .frame(width: 320)
                .background(Color.primary.opacity(0.03))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Right: Detail View (Preview)
                PreviewView(item: selectedItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.08))
            }
        }
        .frame(width: 850, height: 600)
        .background(DesignSystem.backgroundBlur)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
            // Always select first item on appear
            if !displayItems.isEmpty {
                selectedItem = displayItems.first
            }
            // Load favorites on appear
            store.loadFavorites()
        }
        .onChange(of: viewMode) { _, _ in
            // Update selected item or trigger search if query exists
            if !searchText.isEmpty {
                updateSearchResults()
            } else if !displayItems.isEmpty {
                selectedItem = displayItems.first
            } else {
                selectedItem = nil
            }
        }
        .onChange(of: searchText) { _, _ in
            updateSearchResults()
        }
        .onChange(of: selectedItem) { _, _ in
            // Clicking a row moves focus into the list; bring it back so
            // arrow keys / Enter / Esc keep working
            if !isSearchFocused {
                isSearchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            // Only react to the overlay window itself — other windows (Settings,
            // popovers) becoming key must not steal the search focus
            guard notification.object is OverlayWindow else { return }
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .veloxOverlayWillShow)) { _ in
            // Reset state only when the overlay is (re)opened, not every time it
            // regains key status (e.g. after closing a popover)
            isSearchFocused = true
            viewMode = .history
            searchText = ""
            searchTask?.cancel()
            cachedSemanticResults.removeAll()
            if !store.items.isEmpty {
                selectedItem = store.items.first
                scrollTarget = store.items.first?.id
            }
        }
        .errorAlert() // Add unified error handling
    }
    
    private func executeSelection() {
        if let item = selectedItem {
            WindowManager.shared.selectAndPaste(item)
        } else if let first = displayItems.first {
            WindowManager.shared.selectAndPaste(first)
        }
    }
    
    private func moveSelection(direction: Int) {
        let items = displayItems
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex(where: { $0.id == selectedItem?.id }) ?? -1
        let nextIndex = currentIndex + direction

        if nextIndex >= 0 && nextIndex < items.count {
            selectedItem = items[nextIndex]
            // Keyboard navigation keeps the selection in view; mouse clicks never scroll
            scrollTarget = items[nextIndex].id
        }
    }
    
    private var favoriteToggleButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewMode = viewMode == .history ? .favorites : .history
            }
        }) {
            Group {
                if viewMode == .favorites {
                    Image(systemName: "star.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(DesignSystem.primaryGradient)
                } else {
                    Image(systemName: "star")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .help(viewMode == .favorites ? "Show History" : "Show Favorites")
    }
}
