import Foundation
import Combine

@MainActor
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var favoriteItems: [ClipboardItem] = []
    private let dbManager: DatabaseManager
    
    static let shared = ClipboardStore()
    
    init(dbManager: DatabaseManager = DatabaseManager.shared, shouldLoad: Bool = true) {
        self.dbManager = dbManager

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
    func enforceHistoryLimit() {
        guard AppSettings.shared.settingsLoaded else { return }
        let limit = AppSettings.shared.historyLimit

        let regularCount = items.lazy.filter { !$0.isFavorite }.count
        guard regularCount > limit else { return }
        let excessCount = regularCount - limit

        var itemsToRemove: [ClipboardItem] = []
        for item in items.reversed() where !item.isFavorite && itemsToRemove.count < excessCount {
            itemsToRemove.append(item)
        }
        let idsToRemove = Set(itemsToRemove.map(\.id))
        items.removeAll { idsToRemove.contains($0.id) }

        Task {
            for id in idsToRemove {
                try? await dbManager.deleteClipboardItem(id: id)
            }
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

    func updateItem(id: UUID, content: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        var updatedItem = items[index]
        let originalItem = items[index] // Backup for rollback
        
        updatedItem.content = content
        updatedItem.tags.append("OCR")
        
        // Optimistic UI update
        self.items[index] = updatedItem
        
        // Persist to database
        Task {
            do {
                try await dbManager.updateClipboardItem(updatedItem)
            } catch {
                print("Failed to update item: \(error)")
                // Rollback to original state if database update failed
                await MainActor.run {
                    // Find item again by ID (index might have changed)
                    if let currentIndex = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[currentIndex] = originalItem
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
        
        // Persist to database
        do {
            try await dbManager.updateClipboardItem(updatedItem)
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

        var deletedIDs: Set<UUID> = []

        for id in idsToDelete {
            do {
                try await dbManager.deleteClipboardItem(id: id)
                deletedIDs.insert(id)
            } catch {
                print("Failed to delete item \(id): \(error)")
                ErrorHandler.shared.handle(error)
            }
        }

        items.removeAll { deletedIDs.contains($0.id) }
        favoriteItems.removeAll { deletedIDs.contains($0.id) }
    }
    
    func clearAll() {
        Task {
            do {
                try await dbManager.deleteAllClipboardItems()
                
                // Then clear local array
                await MainActor.run {
                    self.items.removeAll()
                }
            } catch {
                print("Failed to clear all items: \(error)")
                Task { @MainActor in
                    ErrorHandler.shared.handle(error)
                }
            }
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
                    self.favoriteItems = loadedFavorites
                }
            } catch {
                print("Failed to load favorites: \(error)")
                Task { @MainActor in
                    ErrorHandler.shared.handle(error)
                    self.favoriteItems = []
                }
            }
        }
    }
    
    private func load() {
        Task {
            do {
                let loadedItems = try await dbManager.fetchAllClipboardItems()
                await MainActor.run {
                    self.items = loadedItems
                    // Load favorites from items
                    self.favoriteItems = loadedItems.filter { $0.isFavorite }
                        .sorted { ($0.favoritedAt ?? $0.createdAt) > ($1.favoritedAt ?? $1.createdAt) }
                }
            } catch {
                print("Failed to load items: \(error)")
                Task { @MainActor in
                    ErrorHandler.shared.handle(error)
                    self.items = []
                    self.favoriteItems = []
                }
            }
        }
    }
}
