import Foundation
import Combine

@MainActor
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var favoriteItems: [ClipboardItem] = []
    private let dbManager = DatabaseManager.shared
    
    static let shared = ClipboardStore()
    
    init() {
        load()
    }
    
    func addItem(_ item: ClipboardItem) {
        // Check if item already exists in local array to avoid duplicates
        if items.contains(where: { $0.id == item.id }) {
            return
        }
        
        // Optimistic UI update for better UX
        self.items.insert(item, at: 0)
        
        // Enforce history limit - only limit non-favorite items
        let limit = AppSettings.shared.historyLimit
        var itemsToRemove: [ClipboardItem] = []
        
        // Separate favorite and regular items
        let regularItems = self.items.filter { !$0.isFavorite }
        let regularCount = regularItems.count
        
        // Only apply limit to non-favorite items
        if regularCount > limit {
            let excessCount = regularCount - limit
            // Collect non-favorite items from the end (oldest first)
            var collected = 0
            for item in self.items.reversed() {
                if !item.isFavorite && collected < excessCount {
                    itemsToRemove.append(item)
                    collected += 1
                }
            }
            // Remove from local array
            for itemToRemove in itemsToRemove {
                if let index = self.items.firstIndex(where: { $0.id == itemToRemove.id }) {
                    self.items.remove(at: index)
                }
            }
        }
        
        // Capture the item ID to safely remove it later if needed
        let itemId = item.id
        
        // Then persist to database asynchronously
        Task {
            do {
                try await dbManager.insertClipboardItem(item)
                
                // Delete excess items from database if any
                for itemToRemove in itemsToRemove {
                    try? await dbManager.deleteClipboardItem(id: itemToRemove.id)
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
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        var updatedItem = items[index]
        let originalItem = items[index] // Backup for rollback
        
        updatedItem.tags = tags
        
        // Optimistic UI update
        self.items[index] = updatedItem
        
        // Update favoriteItems if it's a favorite
        if updatedItem.isFavorite, let favIndex = favoriteItems.firstIndex(where: { $0.id == id }) {
            favoriteItems[favIndex] = updatedItem
        }
        
        // Persist to database
        Task {
            do {
                try await dbManager.updateClipboardItem(updatedItem)
            } catch {
                print("Failed to update tags: \(error)")
                // Rollback to original state if database update failed
                await MainActor.run {
                    // Find item again by ID (index might have changed)
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
        }
    }
    
    func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { items[$0] }
        
        // Delete from database first
        Task {
            for item in itemsToDelete {
                do {
                    try await dbManager.deleteClipboardItem(id: item.id)
                } catch {
                    print("Failed to delete item \(item.id): \(error)")
                }
            }
            
            // Then remove from local array
            await MainActor.run {
                self.items.remove(atOffsets: offsets)
            }
        }
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
