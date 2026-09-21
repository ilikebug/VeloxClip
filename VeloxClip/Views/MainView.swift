import SwiftUI
import SwiftData
import AppKit

struct MainSearchBarLayout {
    static let fontSize: CGFloat = 14
    static let verticalPadding: CGFloat = 14
}

struct MainFocusRoutingPolicy {
    static func shouldRestoreSearchFocus(isDetailPresented: Bool,
                                         isCommandPalettePresented: Bool) -> Bool {
        !isDetailPresented && !isCommandPalettePresented
    }
}

enum ViewMode {
    case favorites
    case history
}

struct MainView: View {
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var selectedItem: ClipboardItem?
    @State private var searchText = ""
    // Focus target for the SEARCH FIELD ONLY (so the user can type immediately on
    // open). Key navigation/commands are handled by a focus-independent window-level
    // NSEvent monitor (see KeyMonitor / handleKeyDown), not by SwiftUI focus.
    @FocusState private var isSearchFocused: Bool
    @State private var viewMode: ViewMode = .history
    @State private var typeFilter: ClipboardTypeFilter = .all
    @StateObject private var search = ClipboardSearchViewModel()
    @State private var scrollTarget: UUID?
    @State private var showCommandPalette = false
    // Push-in detail: nil = list mode; non-nil = detail mode (replaces search+list)
    @State private var detailItem: ClipboardItem?

    // Debounced search text for semantic search
    
    // Cached semantic search results - only store IDs and scores to save memory
    
    var displayItems: [ClipboardItem] {
        let base: [ClipboardItem]
        if searchText.isEmpty {
            base = viewMode == .favorites ? store.favoriteItems : store.items
        } else {
            base = search.results
        }
        // Type filter stacks on top of search results and the favorites view
        guard typeFilter != .all else { return base }
        return base.filter { typeFilter.matches($0) }
    }

    private var emptyKind: EmptyKind {
        if !searchText.isEmpty { return .noMatch }
        return viewMode == .favorites ? .favoritesEmpty : .historyEmpty
    }

    private func restoreSearchFocusSoon() {
        guard MainFocusRoutingPolicy.shouldRestoreSearchFocus(
            isDetailPresented: detailItem != nil,
            isCommandPalettePresented: showCommandPalette
        ) else { return }

        isSearchFocused = true
        Task { @MainActor in
            await Task.yield()
            guard MainFocusRoutingPolicy.shouldRestoreSearchFocus(
                isDetailPresented: detailItem != nil,
                isCommandPalettePresented: showCommandPalette
            ) else { return }
            isSearchFocused = true
        }
    }

    private func openDetail(_ item: ClipboardItem) {
        isSearchFocused = false
        withAnimation(.easeInOut(duration: 0.18)) {
            detailItem = item
        }
    }

    private func updateSearchResults() {
        let baseItems = viewMode == .favorites ? store.favoriteItems : store.items
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            search.clear()
            return
        }
        search.search(query: searchText, in: baseItems) { ranked in
            // Keep the selection valid as results narrow
            if selectedItem == nil || !ranked.contains(where: { $0.id == selectedItem?.id }) {
                selectedItem = ranked.first
                scrollTarget = ranked.first?.id
            }
        }
    }

    
    var body: some View {
        let c = DSColors(scheme: scheme)
        // Navigation/command keys are handled by a window-level NSEvent monitor
        // (focus-independent) so they keep working in detail mode and after the
        // ⌘K palette closes — neither of which holds SwiftUI keyboard focus.
        let base = rootContent(c)
            .background(KeyMonitor(onKeyDown: handleKeyDown))
            .frame(width: OverlayWindowLayout.width, height: OverlayWindowLayout.height)
            .background(DesignSystem.backgroundBlur)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        return applyChrome(base)
    }

    // Command palette overlay + lifecycle hooks, extracted from `body` so the
    // type-checker can handle the expression. `self` is captured at body-eval
    // time, so the closures see live @State exactly as if inlined.
    @ViewBuilder
    private func applyChrome<V: View>(_ content: V) -> some View {
        content
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }
                    CommandPaletteView(item: paletteItem,
                                       isDetailPresented: detailItem != nil,
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
            restoreSearchFocusSoon()
        }
        .onChange(of: typeFilter) { _, _ in
            // Keep the selection inside the filtered list
            if !displayItems.contains(where: { $0.id == selectedItem?.id }) {
                selectedItem = displayItems.first
                scrollTarget = displayItems.first?.id
            }
            restoreSearchFocusSoon()
        }
        .onChange(of: searchText) { _, _ in
            updateSearchResults()
        }
        .onChange(of: showCommandPalette) { _, isPresented in
            if !isPresented {
                restoreSearchFocusSoon()
            }
        }
        .onChange(of: detailItem?.id) { _, detailID in
            if detailID == nil {
                restoreSearchFocusSoon()
            }
        }
        .onChange(of: store.items) { _, newItems in
            // Deleting an item must not leave a ghost row in active search results
            let validIDs = Set(newItems.map(\.id))
            // results are re-derived by the view model on the next query
            // …nor a ghost selection — ⏎ would try to paste an item that no longer
            // exists (for an image that meant clearing the clipboard and pasting nothing)
            if let selected = selectedItem, !validIDs.contains(selected.id) {
                selectedItem = displayItems.first
            }
            if let detail = detailItem, !validIDs.contains(detail.id) {
                withAnimation(.easeInOut(duration: 0.18)) { detailItem = nil }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            // Only react to the overlay window itself — other windows (Settings,
            // popovers) becoming key must not steal the search focus
            guard notification.object is OverlayWindow else { return }
            // Only re-arm search focus in list mode; in detail mode the search field
            // isn't in the tree (this would be a no-op anyway — kept for symmetry).
            if detailItem == nil { restoreSearchFocusSoon() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard notification.object is OverlayWindow else { return }
            showCommandPalette = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .veloxOverlayWillShow)) { _ in
            // Reset state only when the overlay is (re)opened, not every time it
            // regains key status (e.g. after closing a popover)
            showCommandPalette = false
            isSearchFocused = true
            detailItem = nil
            viewMode = .history
            typeFilter = .all
            searchText = ""
            search.clear()
            if !store.items.isEmpty {
                selectedItem = store.items.first
                scrollTarget = store.items.first?.id
            }
        }
        .errorAlert() // Add unified error handling
    }
    
    /// The item the palette acts on: the previewed item in detail mode, else the
    /// list selection — same rule ⌘C already uses.
    private var paletteItem: ClipboardItem? { detailItem ?? selectedItem }

    // The list/detail VStack. Navigation/command keys are routed through the
    // window-level NSEvent monitor in `handleKeyDown` (focus-independent), so there
    // are no `.onKeyPress` handlers here — they only fire while the view tree holds
    // keyboard focus, which is lost in detail mode and after the ⌘K palette closes.
    @ViewBuilder
    private func rootContent(_ c: DSColors) -> some View {
        VStack(spacing: 0) {
            if detailItem == nil {
                listContent(c)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                detailContent(c)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // Focus-independent key routing for the overlay. Installed via `KeyMonitor` as a
    // local NSEvent monitor; return true to consume the event, false to let it fall
    // through to the focused field (so plain typing reaches search / tag / palette).
    //
    // The decision itself lives in MainKeyRouter (pure, unit-tested); this reads
    // the AppKit state and performs the side effects.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // True when the caret is inside an editable text field or a
        // .textSelection(.enabled) preview (the field editor is an NSTextView). In
        // that case text-editing keys (⌘C copy-selection, ← / → cursor movement)
        // must fall through to the responder chain rather than being hijacked for
        // copy-item / open-detail.
        let editingText = event.window?.firstResponder is NSTextView

        let context = MainKeyContext(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers?.lowercased(),
            isCommandPressed: event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .contains(.command),
            isOverlayKeyWindow: event.window is OverlayWindow,
            isPalettePresented: showCommandPalette,
            isDetailPresented: detailItem != nil,
            isEditingText: editingText,
            hasTextSelection: hasTextSelection(in: event.window),
            isComposingText: (event.window?.firstResponder as? NSTextView)?.hasMarkedText() ?? false,
            hasSelection: (detailItem ?? selectedItem) != nil,
            isSearchTextEmpty: searchText.isEmpty,
            visibleItemCount: displayItems.count
        )

        switch MainKeyRouter.route(context) {
        case .passThrough:
            return false
        case .copySelection:
            if let item = detailItem ?? selectedItem { copyItem(item) }
            return true
        case .openPalette:
            showCommandPalette = true
            return true
        case .closeDetail:
            withAnimation(.easeInOut(duration: 0.18)) { detailItem = nil }
            return true
        case .stageSelection:
            if let item = detailItem ?? selectedItem { PasteStackService.shared.toggleStaged(item) }
            return true
        case .pasteSelection:
            executeSelection()
            return true
        case .moveSelection(let delta):
            moveSelection(direction: delta)
            return true
        case .openDetail:
            if let item = selectedItem { openDetail(item) }
            return true
        case .pasteRow(let index):
            guard displayItems.indices.contains(index) else { return false }
            WindowManager.shared.selectAndPaste(displayItems[index])
            return true
        case .clearSearch:
            searchText = ""
            return true
        case .closeOverlay:
            WindowManager.shared.toggleWindow()
            return true
        case .switchTab:
            withAnimation(.easeInOut(duration: 0.2)) {
                viewMode = (viewMode == .history ? .favorites : .history)
            }
            return true
        }
    }

    // True when the window's focused text view has a non-empty selection (so a
    // native ⌘C copy-selection would actually copy something). Used to decide
    // whether ⌘C should fall through to the field or copy the selected item.
    private func hasTextSelection(in window: NSWindow?) -> Bool {
        guard let tv = window?.firstResponder as? NSTextView else { return false }
        return tv.selectedRange().length > 0
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

                TextField(L10n.string("main.search.placeholder", language: settings.appLanguage), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: MainSearchBarLayout.fontSize))
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelection()
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, MainSearchBarLayout.verticalPadding)
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
            ClipboardListView(
                selectedItem: $selectedItem,
                items: displayItems,
                scrollTarget: $scrollTarget,
                emptyKind: emptyKind,
                onUserInteract: { restoreSearchFocusSoon() },
                onContextMenu: { item in
                    selectedItem = item
                    showCommandPalette = true
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom action bar
            Divider().overlay(c.divider)
            HStack(spacing: 14) {
                actionHint(L10n.string("main.action.paste", language: settings.appLanguage), "⏎")
                actionHint(L10n.string("main.action.detail", language: settings.appLanguage), "⌘→")
                actionHint(L10n.string("main.action.stack", language: settings.appLanguage), "⌘⏎")
                actionHint(L10n.string("main.action.actions", language: settings.appLanguage), "⌘K")
                Spacer()
                Text(L10n.format("main.items.count", displayItems.count, language: settings.appLanguage))
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
        // No RightClickCatcher here on purpose: the preview is full of
        // selectable text and a tag field, and the catcher swallows every
        // right-click in its bounds — which stole macOS's own Copy / Look Up /
        // Cut-Paste menus. The action palette belongs to the list.
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
        let item = paletteItem
        // Exhaustive over CommandKind: adding a command is now a compiler error
        // here until it is handled, instead of silently doing nothing.
        switch cmd.kind {
        case .paste:
            if let i = item { WindowManager.shared.selectAndPaste(i) }
        case .copy:
            if let i = item { copyItem(i) }
        case .detail:
            if let i = item, detailItem == nil { openDetail(i) }
        case .copyHex:
            if let content = item?.content {
                copyString(ColorFormatting.hex(from: content) ?? content)
            }
        case .copyRgb:
            if let content = item?.content {
                copyString(ColorFormatting.rgb(from: content) ?? content)
            }
        case .editImage:
            if let i = item { editImage(i) }
        case .openURL:
            if let content = item?.content { openURL(content) }
        case .revealInFinder:
            if let content = item?.content { revealFilesInFinder(content) }
        case .copyPath:
            if let content = item?.content { copyString(content) }
        case .favorite:
            if let i = item { ClipboardStore.shared.toggleFavorite(for: i) }
        case .stack:
            if let i = item { PasteStackService.shared.toggleStaged(i) }
        case .delete:
            if let i = item, let idx = displayItems.firstIndex(where: { $0.id == i.id }) {
                let items = displayItems
                // onChange(of: store.items) drops the selection / detail pane for the removed row
                Task { await ClipboardStore.shared.deleteItems(at: IndexSet(integer: idx), in: items) }
            }
        }
        // Paste dismisses the overlay itself; everything else just closes the palette.
        if cmd.kind != .paste {
            showCommandPalette = false
        }
    }

    // Copy the full item to the pasteboard, preserving its real payload
    // (image/rtf blobs, file URLs) — mirrors WindowManager.selectAndPaste so
    // ⌘K "复制" and ⌘C don't drop non-text content.
    private func copyItem(_ item: ClipboardItem) {
        Task { @MainActor in
            var full = item
            if full.data == nil, full.type == "image" || full.type == "rtf" {
                full.data = await ClipboardStore.shared.loadData(for: item.id)
            }
            PasteboardService.shared.write(item: full)
        }
    }

    // Copy a plain string (used by copyHex/copyRgb — hex/rgb are text values).
    private func copyString(_ string: String) {
        PasteboardService.shared.write(text: string)
    }

    private func editImage(_ item: ClipboardItem) {
        Task { @MainActor in
            var full = item
            if full.data == nil {
                full.data = await ClipboardStore.shared.loadData(for: item.id)
            }
            guard let data = full.data, let nsImage = NSImage(data: data) else { return }
            ScreenshotEditorService.shared.showEditor(with: nsImage)
        }
    }

    private func openURL(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), WebURL.isOpenable(url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealFilesInFinder(_ content: String) {
        let urls = RowPresentation.filePaths(from: content)
            .map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func moveSelection(direction: Int) {
        let items = displayItems
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex(where: { $0.id == selectedItem?.id }) ?? -1
        let nextIndex = currentIndex + direction

        if nextIndex >= 0 && nextIndex < items.count {
            selectedItem = items[nextIndex]
            restoreSearchFocusSoon()
            // Keyboard navigation keeps the selection in view; mouse clicks never scroll
            scrollTarget = items[nextIndex].id
        }
    }
    
    private var dsc: DSColors { DSColors(scheme: scheme) }

    // History / Favorites underline tabs
    private var viewModeTabs: some View {
        HStack(spacing: 18) {
            tabSegment(mode: .history) {
                Text(L10n.string("main.tab.history", language: settings.appLanguage))
            }
            tabSegment(mode: .favorites) {
                HStack(spacing: 5) {
                    Text(L10n.string("main.tab.favorites", language: settings.appLanguage))
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
                    Text(filter.label(language: settings.appLanguage))
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
