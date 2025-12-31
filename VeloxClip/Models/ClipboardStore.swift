import Foundation
import Combine

@MainActor
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
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
        
        // Enforce history limit
        let limit = AppSettings.shared.historyLimit
        var itemsToRemove: [ClipboardItem] = []
        if self.items.count > limit {
            itemsToRemove = Array(self.items.suffix(self.items.count - limit))
            self.items = Array(self.items.prefix(limit))
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
    
    private func load() {
        Task {
            do {
                let loadedItems = try await dbManager.fetchAllClipboardItems()
                await MainActor.run {
                    self.items = loadedItems
                }
            } catch {
                print("Failed to load items: \(error)")
                Task { @MainActor in
                    ErrorHandler.shared.handle(error)
                    self.items = []
                }
            }
        }
    }
}
