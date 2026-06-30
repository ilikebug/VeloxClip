import Foundation

// Bounded cache with true FIFO eviction by insertion order.
// Dictionary.keys.first is unordered, so naive "evict keys.first" implementations
// actually evict a random entry — this type is the single shared fix.
struct FIFOCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var insertionOrder: [Key] = []
    private let maxEntries: Int

    init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    var count: Int { storage.count }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            guard let newValue else {
                if storage.removeValue(forKey: key) != nil {
                    insertionOrder.removeAll { $0 == key }
                }
                return
            }
            if storage[key] == nil {
                if insertionOrder.count >= maxEntries, !insertionOrder.isEmpty {
                    storage.removeValue(forKey: insertionOrder.removeFirst())
                }
                insertionOrder.append(key)
            }
            storage[key] = newValue
        }
    }

    mutating func removeAll() {
        storage.removeAll()
        insertionOrder.removeAll()
    }
}
