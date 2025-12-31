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
        
        // Update local array first for immediate UI update
        self.items.insert(item, at: 0)
        
        // Enforce history limit
        let limit = AppSettings.shared.historyLimit
        var itemsToRemove: [ClipboardItem] = []
        if self.items.count > limit {
            itemsToRemove = Array(self.items.suffix(self.items.count - limit))
            self.items = Array(self.items.prefix(limit))
        }
        
        // Then insert into database asynchronously
        Task {
            do {
                try await dbManager.insertClipboardItem(item)
                
                // Delete excess items from database if any
                for itemToRemove in itemsToRemove {
                    try? await dbManager.deleteClipboardItem(id: itemToRemove.id)
                }
            } catch {
                print("Failed to add item to database: \(error)")
                // Remove from local array if database insert failed
                await MainActor.run {
                    if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items.remove(at: index)
                    }
                }
                Task { @MainActor in
                    ErrorHandler.shared.handle(error)
                }
            }
        }
    }
    
    func updateItem(id: UUID, content: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        var updatedItem = items[index]
        updatedItem.content = content
        updatedItem.tags.append("OCR")
        
        // Update in database first
        Task {
            do {
                try await dbManager.updateClipboardItem(updatedItem)
                
                // Then update local array
                await MainActor.run {
                    self.items[index] = updatedItem
                }
            } catch {
                print("Failed to update item: \(error)")
                Task { @MainActor in
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
