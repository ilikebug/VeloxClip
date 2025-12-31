import Foundation
import Combine

@MainActor
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private let savePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".velox_clips.json")
    
    static let shared = ClipboardStore()
    
    init() {
        load()
    }
    
    func addItem(_ item: ClipboardItem) {
        self.items.insert(item, at: 0)
        
        // Enforce history limit
        let limit = AppSettings.shared.historyLimit
        if self.items.count > limit {
            self.items = Array(self.items.prefix(limit))
        }
        
        self.save()
    }
    
    func updateItem(id: UUID, content: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].content = content
            items[index].tags.append("OCR")
            self.save()
        }
    }
    
    func deleteItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }
    
    func clearAll() {
        items.removeAll()
        save()
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: savePath)
        } catch {
            print("Failed to save items: \(error)")
            // Notify user about save failure using ErrorHandler
            Task { @MainActor in
                ErrorHandler.shared.handle(error)
            }
        }
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: savePath)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            print("No existing clips found or failed to load.")
            items = []
        }
    }
}
