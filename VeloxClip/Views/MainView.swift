import SwiftUI
import SwiftData
import AppKit

enum ViewMode {
    case favorites
    case history
}

struct MainView: View {
    @ObservedObject var store = ClipboardStore.shared
    @Environment(\.colorScheme) private var scheme
    @State private var selectedItem: ClipboardItem?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var viewMode: ViewMode = .history
    @State private var typeFilter: ClipboardTypeFilter = .all
    @State private var searchResults: [ClipboardItem] = []
    @State private var isSearching = false
    @State private var scrollTarget: UUID?
    @State private var showCommandPalette = false
    // Push-in detail: nil = list mode; non-nil = detail mode (replaces search+list)
    @State private var detailItem: ClipboardItem?

    // Debounced search text for semantic search
    @State private var searchTask: Task<Void, Never>?
    
    // Cached semantic search results - only store IDs and scores to save memory
    @State private var cachedSemanticResults = FIFOCache<String, [(UUID, Double)]>(maxEntries: 50)
    
    var displayItems: [ClipboardItem] {
        let base: [ClipboardItem]
        if searchText.isEmpty {
            base = viewMode == .favorites ? store.favoriteItems : store.items
        } else {
            base = searchResults
        }
        // Type filter stacks on top of search results and the favorites view
        guard typeFilter != .all else { return base }
        return base.filter { typeFilter.matches($0) }
    }

    private var emptyKind: EmptyKind {
        if !searchText.isEmpty { return .noMatch }
        return viewMode == .favorites ? .favoritesEmpty : .historyEmpty
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
        let c = DSColors(scheme: scheme)
        // Key handlers live on this always-present outer VStack so Esc / ← / ⏎
        // still reach them in detail mode (where the search field is hidden).
        VStack(spacing: 0) {
            if detailItem == nil {
                listContent(c)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                detailContent(c)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // NOTE: use FILTERED key handlers (keyed `onKeyPress(keys:)`), never an
        // unfiltered `onKeyPress { }` catch-all here — an unfiltered handler
        // alongside the keyed ones below stops the keyed handlers (arrows /
        // return / tab / space / escape) from firing.
        .onKeyPress(keys: ["k"]) { press in
            // ⌘K opens the command palette (list mode only — see guard below it's fine in detail too but commands act on selection).
            guard press.modifiers.contains(.command) else { return .ignored }
            showCommandPalette = true
            return .handled
        }
        .onKeyPress(keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]) { press in
            // ⌘1–9 pastes the corresponding visible row — list mode only.
            guard detailItem == nil else { return .ignored }
            guard press.modifiers.contains(.command),
                  let n = Int(press.characters), n >= 1, n <= 9,
                  displayItems.indices.contains(n - 1) else { return .ignored }
            WindowManager.shared.selectAndPaste(displayItems[n - 1])
            return .handled
        }
        .onKeyPress(.rightArrow) {
            // → opens the push-in detail for the current selection (list mode only).
            guard detailItem == nil, let item = selectedItem else { return .ignored }
            withAnimation(.easeInOut(duration: 0.18)) { detailItem = item }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            // ← returns to the list from detail mode.
            guard detailItem != nil else { return .ignored }
            withAnimation(.easeInOut(duration: 0.18)) { detailItem = nil }
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard detailItem == nil else { return .ignored }
            moveSelection(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard detailItem == nil else { return .ignored }
            moveSelection(direction: 1)
            return .handled
        }
        .onKeyPress(.return) {
            // ⏎ pastes in both modes.
            executeSelection()
            return .handled
        }
        .onKeyPress(.tab) {
            guard detailItem == nil else { return .ignored }
            if isSearchFocused {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewMode = viewMode == .history ? .favorites : .history
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            // Space stages only in list mode while the query is empty — otherwise it
            // must keep typing spaces into the search field.
            guard detailItem == nil else { return .ignored }
            guard searchText.isEmpty, let item = selectedItem else { return .ignored }
            PasteStackService.shared.toggleStaged(item)
            return .handled
        }
        .onKeyPress(.escape) {
            // In detail mode Esc returns to the list (does NOT close the overlay).
            if detailItem != nil {
                withAnimation(.easeInOut(duration: 0.18)) { detailItem = nil }
                return .handled
            }
            // The palette's own handler closes it first; only toggle the
            // overlay when the palette isn't open.
            guard !showCommandPalette else { return .ignored }
            WindowManager.shared.toggleWindow()
            return .handled
        }
        .frame(width: 560, height: 600)
        .background(DesignSystem.backgroundBlur)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }
                    CommandPaletteView(item: selectedItem,
                                       onExecute: { executeCommand($0) },
                                       onClose: { showCommandPalette = false })
                }
            }
        }
        .onAppear {
            isSearchFocused = true
            // First open: the focus set above is dropped if the window isn't key yet,
            // and the didBecomeKey notification fired before this view subscribed —
            // re-assert once the window has had time to become key
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !isSearchFocused {
                    isSearchFocused = true
                }
            }
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
        .onChange(of: typeFilter) { _, _ in
            // Keep the selection inside the filtered list
            if !displayItems.contains(where: { $0.id == selectedItem?.id }) {
                selectedItem = displayItems.first
                scrollTarget = displayItems.first?.id
            }
        }
        .onChange(of: searchText) { _, _ in
            updateSearchResults()
        }
        .onChange(of: store.items) { _, newItems in
            // Deleting an item must not leave a ghost row in active search results
            guard !searchResults.isEmpty else { return }
            let validIDs = Set(newItems.map(\.id))
            searchResults.removeAll { !validIDs.contains($0.id) }
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
            detailItem = nil
            viewMode = .history
            typeFilter = .all
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
    
    // List mode: search bar + tabs/chips + single-column list + action bar.
    @ViewBuilder
    private func listContent(_ c: DSColors) -> some View {
        VStack(spacing: 0) {
            // Top: Compact Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(c.text2)

                TextField("搜索剪贴…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelection()
                    }

                DSKeyBadge(label: "⌘V")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DesignSystem.backgroundBlur)

            Divider().overlay(c.divider)

            // Tabs + type chips, then the single-column list filling the width.
            HStack {
                viewModeTabs
                Spacer()
                typeFilterBar
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 8)
            Divider().overlay(c.divider)
            ClipboardListView(selectedItem: $selectedItem, items: displayItems, scrollTarget: $scrollTarget, emptyKind: emptyKind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom action bar
            Divider().overlay(c.divider)
            HStack(spacing: 14) {
                actionHint("粘贴", "⏎")
                actionHint("详情", "→")
                actionHint("入栈", "space")
                actionHint("动作", "⌘K")
                Spacer()
                Text("\(displayItems.count) 条")
                    .font(.system(size: 11))
                    .foregroundColor(c.text3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // Detail mode: push-in preview filling the window, with ‹ 返回 / ✕ 关闭.
    @ViewBuilder
    private func detailContent(_ c: DSColors) -> some View {
        PreviewView(
            item: detailItem,
            onBack: { withAnimation(.easeInOut(duration: 0.18)) { detailItem = nil } },
            onClose: { WindowManager.shared.toggleWindow() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.04))
    }

    private func executeSelection() {
        // In detail mode, paste the item being previewed.
        if let detail = detailItem {
            WindowManager.shared.selectAndPaste(detail)
        } else if let item = selectedItem {
            WindowManager.shared.selectAndPaste(item)
        } else if let first = displayItems.first {
            WindowManager.shared.selectAndPaste(first)
        }
    }
    
    private func executeCommand(_ cmd: Command) {
        let item = selectedItem
        switch cmd.id {
        case "paste":
            if let i = item { WindowManager.shared.selectAndPaste(i) }
        case "copy":
            copyToPasteboard(item?.content)
        case "detail":
            if let i = item { withAnimation(.easeInOut(duration: 0.18)) { detailItem = i } }
        case "copyHex":
            if let content = item?.content {
                copyToPasteboard(ColorFormatting.hex(from: content) ?? content)
            }
        case "copyRgb":
            if let content = item?.content {
                copyToPasteboard(ColorFormatting.rgb(from: content) ?? content)
            }
        case "favorite":
            if let i = item { ClipboardStore.shared.toggleFavorite(for: i) }
        case "stack":
            if let i = item { PasteStackService.shared.toggleStaged(i) }
        case "delete":
            if let i = item, let idx = displayItems.firstIndex(where: { $0.id == i.id }) {
                let items = displayItems
                Task { await ClipboardStore.shared.deleteItems(at: IndexSet(integer: idx), in: items) }
            }
        default:
            break
        }
        // Paste dismisses the overlay itself; everything else just closes the palette.
        if cmd.id != "paste" {
            showCommandPalette = false
        }
    }

    private func copyToPasteboard(_ string: String?) {
        guard let string else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
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
    
    private var dsc: DSColors { DSColors(scheme: scheme) }

    // 历史 / 收藏 underline tabs
    private var viewModeTabs: some View {
        HStack(spacing: 18) {
            tabSegment(mode: .history) { Text("历史") }
            tabSegment(mode: .favorites) {
                HStack(spacing: 5) {
                    Text("收藏")
                    DSKeyBadge(label: "⇥")
                }
            }
        }
    }

    private func tabSegment<Label: View>(mode: ViewMode, @ViewBuilder label: () -> Label) -> some View {
        let c = dsc
        let selected = viewMode == mode
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewMode = mode
            }
        }) {
            label()
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? c.text : c.text2)
                .padding(.bottom, 7)
                .overlay(alignment: .bottom) {
                    if selected {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(c.accent)
                            .frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // Type chips: content-width pills beside the tabs
    private var typeFilterBar: some View {
        let c = dsc
        return HStack(spacing: 6) {
            ForEach(ClipboardTypeFilter.allCases) { filter in
                let selected = typeFilter == filter
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        typeFilter = filter
                    }
                }) {
                    Text(filter.label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(selected ? .white : c.text2)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(selected ? c.accent : c.chip)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func actionHint(_ label: String, _ key: String?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(dsc.text2)
            if let key { DSKeyBadge(label: key) }
        }
    }
}
