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
    
    // Debounced search text for semantic search
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?
    
    // Cached semantic search results - only store IDs and scores to save memory
    @State private var cachedSemanticResults: [String: [(UUID, Double)]] = [:]
    
    var filteredItems: [ClipboardItem] {
        // Get base items based on view mode
        let baseItems = viewMode == .favorites ? store.favoriteItems : store.items
        
        if searchText.isEmpty {
            return baseItems
        } else {
            let trimmedQuery = searchText.trimmingCharacters(in: .whitespaces)
            
            // Keyword search (exact matches)
            let keywordMatches = baseItems.filter { item in
                item.content?.localizedCaseInsensitiveContains(trimmedQuery) ?? false ||
                item.type.localizedCaseInsensitiveContains(trimmedQuery) ||
                (item.sourceApp?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
                item.tags.contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) })
            }
            
            // Always perform semantic search for queries longer than 2 characters
            // This provides better results even when there are keyword matches
            var allMatches: [(ClipboardItem, Double)] = []
            
            // Add keyword matches with high score
            let keywordMatchIds = Set(keywordMatches.map { $0.id })
            for item in keywordMatches {
                allMatches.append((item, 1.0))
            }
            
            // Add semantic matches (with scores already calculated)
            // Use debounced search text for semantic search to avoid frequent recalculations
            // But if debounced text is empty or different, use current query for immediate feedback
            if trimmedQuery.count >= 2 {
                // Always use current query for semantic search to ensure consistency
                // The performSemanticSearch function will handle caching internally
                let semanticMatches = performSemanticSearch(query: trimmedQuery)
                for (itemId, similarity) in semanticMatches {
                    // Avoid duplicates with keyword matches
                    if !keywordMatchIds.contains(itemId) {
                        // Look up the actual item from base items
                        if let item = baseItems.first(where: { $0.id == itemId }) {
                            allMatches.append((item, similarity))
                        }
                    }
                }
            }
            
            // Sort by score (keyword matches first, then by similarity, favorites prioritized in history view)
            let sorted = allMatches.sorted { item1, item2 in
                // Exact matches first
                if item1.1 == 1.0 && item2.1 != 1.0 {
                    return true
                }
                if item1.1 != 1.0 && item2.1 == 1.0 {
                    return false
                }
                // In history view, prioritize favorites
                if viewMode == .history {
                    if item1.0.isFavorite && !item2.0.isFavorite {
                        return true
                    }
                    if !item1.0.isFavorite && item2.0.isFavorite {
                        return false
                    }
                }
                // Then by similarity score
                return item1.1 > item2.1
            }
            
            return sorted.map { $0.0 }
        }
    }
    
    private func performSemanticSearch(query: String) -> [(UUID, Double)] {
        // Check cache first
        let normalizedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()
        if let cached = cachedSemanticResults[normalizedQuery] {
            return cached
        }
        
        guard let queryVector = AIService.shared.generateEmbedding(for: query) else {
            return []
        }
        
        // Lower threshold for better recall (0.5 instead of 0.7)
        // This allows more semantically related results to appear
        let threshold = 0.5
        
        // Also limit results to top 20 most similar items for performance
        let maxResults = 20
        
        // Filter items that have embeddings first (performance optimization)
        let baseItems = viewMode == .favorites ? store.favoriteItems : store.items
        let itemsWithEmbeddings = baseItems.filter { item in
            item.content != nil && !item.content!.isEmpty && item.vector != nil
        }
        
        // Early return if no items have embeddings
        guard !itemsWithEmbeddings.isEmpty else {
            return []
        }
        
        // Calculate similarities - only store IDs and scores in cache
        let results = itemsWithEmbeddings.compactMap { item -> (UUID, Double)? in
            guard let itemVector = item.vector else {
                return nil
            }
            
            let similarity = AIService.shared.calculateSimilarity(queryVector, itemVector)
            return similarity >= threshold ? (item.id, similarity) : nil
        }
        .sorted { $0.1 > $1.1 } // Sort by similarity score
        .prefix(maxResults) // Limit to top results
        
        let finalResults = Array(results)
        
        // Cache the results (limit cache size) - only IDs and scores, not full items
        if cachedSemanticResults.count >= 50 {
            // Remove oldest entries
            let keysToRemove = Array(cachedSemanticResults.keys.prefix(10))
            for key in keysToRemove {
                cachedSemanticResults.removeValue(forKey: key)
            }
        }
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
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Bottom Content: List and Preview
            HStack(spacing: 0) {
                // Left: Clipboard List (History)
                VStack(spacing: 0) {
                    ClipboardListView(selectedItem: $selectedItem, items: filteredItems)
                }
                .frame(width: 320)
                .background(Color.black.opacity(0.02))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Right: Detail View (Preview)
                PreviewView(item: selectedItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.05))
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
            if !filteredItems.isEmpty {
                selectedItem = filteredItems.first
            }
            // Load favorites on appear
            store.loadFavorites()
        }
        .onChange(of: viewMode) { _ in
            // Update selected item when switching views
            if !filteredItems.isEmpty {
                selectedItem = filteredItems.first
            } else {
                selectedItem = nil
            }
        }
        .onChange(of: searchText) { newValue in
            // Auto select first on search
            selectedItem = filteredItems.first
            
            // Debounce semantic search (300ms delay)
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if !Task.isCancelled {
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    debouncedSearchText = trimmed
                    // Trigger UI update after debounced text changes
                    // This ensures filteredItems recalculates with cached semantic results
                    if !trimmed.isEmpty && trimmed.count >= 2 {
                        selectedItem = filteredItems.first
                    }
                }
            }
        }
        .onChange(of: debouncedSearchText) { newValue in
            // When debounced text updates, recalculate filtered items
            // This ensures semantic search cache is used when user stops typing
            if !newValue.isEmpty {
                selectedItem = filteredItems.first
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isSearchFocused = true
            // Reset state when window opens
            viewMode = .history
            searchText = ""
            debouncedSearchText = ""
            debounceTask?.cancel()
            cachedSemanticResults.removeAll() // Clear cache when window closes
            if !store.items.isEmpty {
                // We use 'store.items' (full list) because we just cleared search
                selectedItem = store.items.first
            }
        }
        .errorAlert() // Add unified error handling
    }
    
    private func executeSelection() {
        if let item = selectedItem {
            WindowManager.shared.selectAndPaste(item)
        } else if let first = filteredItems.first {
            WindowManager.shared.selectAndPaste(first)
        }
    }
    
    private func moveSelection(direction: Int) {
        let items = filteredItems
        guard !items.isEmpty else { return }
        
        let currentIndex = items.firstIndex(where: { $0.id == selectedItem?.id }) ?? -1
        let nextIndex = currentIndex + direction
        
        if nextIndex >= 0 && nextIndex < items.count {
            selectedItem = items[nextIndex]
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
