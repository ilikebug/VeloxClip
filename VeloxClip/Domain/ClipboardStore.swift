import Foundation
import Combine

@MainActor
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var favoriteItems: [ClipboardItem] = []
    private let dbManager: DatabaseManager
    private let settings: AppSettings

    static let shared = ClipboardStore()

    init(dbManager: DatabaseManager = DatabaseManager.shared,
         settings: AppSettings = AppSettings.shared,
         shouldLoad: Bool = true) {
        self.dbManager = dbManager
        self.settings = settings

        // Shrinking the limit takes effect immediately, not on the next copy
        settings.onHistoryLimitChanged = { [weak self] in
            self?.enforceHistoryLimit()
        }

        if shouldLoad {
            load()
        }
    }

    func addItem(_ item: ClipboardItem) {
        // Content-based Deduplication: Check if an item with the same content/data already exists.
        // Blobs are compared via dataHash so this never touches multi-megabyte Data values.
        if let existingIndex = items.firstIndex(where: {
            $0.type == item.type && (
                ($0.content != nil && $0.content == item.content) ||
                ($0.dataHash != nil && $0.dataHash == item.dataHash)
            )
        }) {
            // Move existing item to top, keeping the original copy time
            var existingItem = items[existingIndex]
            existingItem.lastUsedAt = Date()

            // UI Update: Move to start of array
            self.items.remove(at: existingIndex)
            self.items.insert(existingItem, at: 0)

            // Sync favorites list if needed
            if existingItem.isFavorite {
                if let favIndex = favoriteItems.firstIndex(where: { $0.id == existingItem.id }) {
                    favoriteItems.remove(at: favIndex)
                    favoriteItems.insert(existingItem, at: 0)
                }
            }

            // Persist update — only lastUsedAt changed
            let usedAt = existingItem.lastUsedAt ?? Date()
            let existingID = existingItem.id
            Task {
                try? await dbManager.touchItem(id: existingID, lastUsedAt: usedAt)
            }
            return
        }

        // Optimistic UI update for better UX
        self.items.insert(item, at: 0)

        enforceHistoryLimit()

        // Capture the item ID to safely remove it later if needed
        let itemId = item.id

        // Then persist to database asynchronously
        Task {
            do {
                try await dbManager.insertClipboardItem(item)

                // Blob is now persisted — drop it from memory; previews lazy-load via loadData(for:)
                if item.data != nil, let index = self.items.firstIndex(where: { $0.id == itemId }) {
                    self.items[index].data = nil
                }
            } catch {
                print("Failed to add item to database: \(error)")
                // Rollback UI change if database insert failed
                // Use captured ID instead of relying on index
                await MainActor.run {
                    // Only remove if the item still exists and hasn't been modified
                    if let index = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items.remove(at: index)
                    }
                    ErrorHandler.shared.handle(error)
                }
            }
        }
    }

    // Trim non-favorite items beyond the configured limit (favorites never count).
    // Guarded on settingsLoaded: during the launch window historyLimit still
    // holds its default, and trimming against it could mass-delete history.
    // A non-positive limit is invalid (AppSettings rejects it on load) and means "don't trim".
    func enforceHistoryLimit() {
        guard settings.settingsLoaded else { return }
        let limit = settings.historyLimit
        guard limit > 0 else { return }

        let regularCount = items.lazy.filter { !$0.isFavorite }.count
        guard regularCount > limit else { return }
        let excessCount = regularCount - limit

        var itemsToRemove: [ClipboardItem] = []
        for item in items.reversed() where !item.isFavorite && itemsToRemove.count < excessCount {
            itemsToRemove.append(item)
        }
        let idsToRemove = itemsToRemove.map(\.id)
        let removeSet = Set(idsToRemove)
        items.removeAll { removeSet.contains($0.id) }

        Task {
            try? await dbManager.deleteClipboardItems(ids: idsToRemove)
        }
    }

    // Loads the blob for an item on demand (list queries don't fetch the data column)
    func loadData(for id: UUID) async -> Data? {
        if let item = items.first(where: { $0.id == id }) ?? favoriteItems.first(where: { $0.id == id }),
           let data = item.data {
            return data
        }
        return try? await dbManager.fetchItemData(id: id)
    }

    // Called when the user pastes/copies an existing item: move it to the top
    // without rewriting createdAt, so the original copy time is preserved
    func markUsed(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        var item = items.remove(at: index)
        let usedAt = Date()
        item.lastUsedAt = usedAt
        items.insert(item, at: 0)

        if item.isFavorite, let favIndex = favoriteItems.firstIndex(where: { $0.id == id }) {
            favoriteItems[favIndex] = item
        }

        Task {
            try? await dbManager.touchItem(id: id, lastUsedAt: usedAt)
        }
    }

    /// OCR result for an image item: sets the text and adds the "OCR" tag.
    func updateItem(id: UUID, content: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        var updatedItem = items[index]
        let originalItem = items[index] // Backup for rollback

        updatedItem.content = content
        if !updatedItem.tags.contains("OCR") {
            updatedItem.tags.append("OCR")
        }

        // Optimistic UI update
        self.items[index] = updatedItem

        // Keep the favorites list in sync — a favorited screenshot must show
        // its OCR text there too
        if updatedItem.isFavorite, let favIndex = favoriteItems.firstIndex(where: { $0.id == id }) {
            favoriteItems[favIndex] = updatedItem
        }

        // Persist only the columns that changed — a full-row write from this
        // snapshot could undo a favorite toggle that landed meanwhile
        let newTags = updatedItem.tags
        Task {
            do {
                try await dbManager.updateContent(id: id, content: content, tags: newTags)
            } catch {
                print("Failed to update item: \(error)")
                // Rollback to original state if database update failed
                await MainActor.run {
                    // Find item again by ID (index might have changed)
                    if let currentIndex = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[currentIndex] = originalItem
                    }
                    if originalItem.isFavorite, let favIndex = self.favoriteItems.firstIndex(where: { $0.id == id }) {
                        self.favoriteItems[favIndex] = originalItem
                    }
                    ErrorHandler.shared.handle(error)
                }
            }
        }
    }

    func updateTags(id: UUID, tags: [String]) {
        Task {
            await updateMetadata(id: id, tags: tags)
        }
    }

    /// Replaces the tag list and/or embedding (user tag edits pass the full list).
    func updateMetadata(id: UUID, tags: [String]? = nil, embedding: Data? = nil) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        var updatedItem = items[index]
        let originalItem = items[index] // Backup for rollback

        if let tags {
            updatedItem.tags = tags
        }

        if let embedding {
            updatedItem.embedding = embedding
        }

        // Optimistic UI update
        self.items[index] = updatedItem

        // Update favoriteItems if it's a favorite
        if updatedItem.isFavorite, let favIndex = favoriteItems.firstIndex(where: { $0.id == id }) {
            favoriteItems[favIndex] = updatedItem
        }

        // Persist only tags/embedding — never the favorite columns from this snapshot
        do {
            try await dbManager.updateDetectedMetadata(id: id, tags: updatedItem.tags, embedding: embedding)
        } catch {
            print("Failed to update metadata: \(error)")
            // Rollback to original state if database update failed
            if let currentIndex = self.items.firstIndex(where: { $0.id == id }) {
                self.items[currentIndex] = originalItem
            }
            // Also rollback favoriteItems
            if originalItem.isFavorite, let favIndex = self.favoriteItems.firstIndex(where: { $0.id == id }) {
                self.favoriteItems[favIndex] = originalItem
            }
            ErrorHandler.shared.handle(error)
        }
    }

    /// Background analysis result (auto-tags + embedding). Auto-tags are MERGED into
    /// whatever tags the item has by now, so a tag the user added while the analysis
    /// was running is kept.
    func applyDetectedMetadata(id: UUID, tags detected: [String], embedding: Data?) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var merged = items[index].tags
        for tag in detected where !merged.contains(tag) {
            merged.append(tag)
        }
        await updateMetadata(id: id, tags: merged, embedding: embedding)
    }

    func addTag(_ tag: String, to item: ClipboardItem) {
        var updatedTags = item.tags
        if !updatedTags.contains(tag) {
            updatedTags.append(tag)
            updateTags(id: item.id, tags: updatedTags)
        }
    }

    func removeTag(_ tag: String, from item: ClipboardItem) {
        var updatedTags = item.tags
        updatedTags.removeAll { $0 == tag }
        updateTags(id: item.id, tags: updatedTags)
    }

    func deleteItems(at offsets: IndexSet, in visibleItems: [ClipboardItem]) async {
        let idsToDelete: Set<UUID> = Set(offsets.compactMap { index in
            guard visibleItems.indices.contains(index) else { return nil }
            return visibleItems[index].id
        })

        guard !idsToDelete.isEmpty else { return }

        do {
            try await dbManager.deleteClipboardItems(ids: Array(idsToDelete))
        } catch {
            print("Failed to delete items: \(error)")
            ErrorHandler.shared.handle(error)
            return
        }

        items.removeAll { idsToDelete.contains($0.id) }
        favoriteItems.removeAll { idsToDelete.contains($0.id) }
    }

    /// Deletes every non-favorite item. Favorites are a separate collection the
    /// user curated; "clear history" must not take them down with it.
    func clearHistory() async {
        do {
            try await dbManager.deleteNonFavoriteItems()
            items.removeAll { !$0.isFavorite }
        } catch {
            print("Failed to clear history: \(error)")
            ErrorHandler.shared.handle(error)
        }
    }

    func toggleFavorite(for item: ClipboardItem) {
        let itemId = item.id

        // Optimistic UI update
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            var updatedItem = items[index]
            updatedItem.isFavorite.toggle()
            updatedItem.favoritedAt = updatedItem.isFavorite ? Date() : nil
            items[index] = updatedItem

            // Update favoriteItems list
            if updatedItem.isFavorite {
                if !favoriteItems.contains(where: { $0.id == itemId }) {
                    favoriteItems.insert(updatedItem, at: 0)
                }
            } else {
                favoriteItems.removeAll(where: { $0.id == itemId })
            }
        }

        // Persist to database
        Task {
            do {
                try await dbManager.toggleFavorite(id: itemId)
            } catch {
                print("Failed to toggle favorite: \(error)")
                // Rollback UI change
                await MainActor.run {
                    if let index = self.items.firstIndex(where: { $0.id == itemId }) {
                        var revertedItem = self.items[index]
                        revertedItem.isFavorite = item.isFavorite
                        revertedItem.favoritedAt = item.favoritedAt
                        self.items[index] = revertedItem

                        // Update favoriteItems list
                        if revertedItem.isFavorite {
                            if !self.favoriteItems.contains(where: { $0.id == itemId }) {
                                self.favoriteItems.insert(revertedItem, at: 0)
                            }
                        } else {
                            self.favoriteItems.removeAll(where: { $0.id == itemId })
                        }
                    }
                    ErrorHandler.shared.handle(error)
                }
            }
        }
    }

    func loadFavorites() {
        Task {
            do {
                let loadedFavorites = try await dbManager.fetchFavoriteItems()
                await MainActor.run {
                    // Merge for the same reason load() does: this runs on every
                    // overlay/menu-bar appearance, and a favorite toggled while
                    // the read was in flight must not be clobbered by the snapshot.
                    let loadedIDs = Set(loadedFavorites.map(\.id))
                    let liveOnly = self.favoriteItems.filter { !loadedIDs.contains($0.id) }
                    self.favoriteItems = (loadedFavorites + liveOnly)
                        .sorted { ($0.favoritedAt ?? $0.createdAt) > ($1.favoritedAt ?? $1.createdAt) }
                }
            } catch {
                // Keep whatever is on screen — a transient read failure must not
                // blank the favorites list
                print("Failed to load favorites: \(error)")
                Task { @MainActor in
                    ErrorHandler.shared.handle(error)
                }
            }
        }
    }

    private func load() {
        Task {
            do {
                let loadedItems = try await dbManager.fetchAllClipboardItems()
                await MainActor.run {
                    // Merge, never replace. `shared` is created lazily — often by
                    // the monitor's first ingest — so items can be inserted while
                    // this read is in flight. Replacing the array wholesale threw
                    // them away: still in SQLite, gone from the UI until relaunch.
                    let loadedIDs = Set(loadedItems.map(\.id))
                    let liveOnly = self.items.filter { !loadedIDs.contains($0.id) }
                    self.items = (loadedItems + liveOnly)
                        .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
                    self.favoriteItems = self.items.filter { $0.isFavorite }
                        .sorted { ($0.favoritedAt ?? $0.createdAt) > ($1.favoritedAt ?? $1.createdAt) }
                }
            } catch {
                print("Failed to load items: \(error)")
                Task { @MainActor in
                    ErrorHandler.shared.handle(error)
                }
            }
        }
    }
}
