import Foundation

// Bounded cache with true FIFO eviction by insertion order.
// Dictionary.keys.first is unordered, so naive "evict keys.first" implementations
// actually evict a random entry — this type is the single shared fix.
//
// An entry-count bound alone is not enough for the preview caches: they are keyed
// on the full document text and hold derived copies of it, so 100 entries of a
// one-megabyte document pinned hundreds of megabytes for the rest of the session
// with no release short of Settings → Clear Cache. Callers holding large values
// pass a byte budget and a sizer; callers with small values omit both and keep
// the original behaviour.
struct FIFOCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var insertionOrder: [Key] = []
    private var sizes: [Key: Int] = [:]
    private let maxEntries: Int
    private let maxBytes: Int?
    private let sizeOf: ((Key, Value) -> Int)?

    private(set) var byteCount = 0

    init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = nil
        self.sizeOf = nil
    }

    init(maxEntries: Int, maxBytes: Int, sizeOf: @escaping (Key, Value) -> Int) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
        self.sizeOf = sizeOf
    }

    var count: Int { storage.count }

    /// Zero when this cache is bounded by entry count only.
    var byteLimit: Int { maxBytes ?? 0 }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            guard let newValue else {
                if storage.removeValue(forKey: key) != nil {
                    insertionOrder.removeAll { $0 == key }
                    byteCount -= sizes.removeValue(forKey: key) ?? 0
                }
                return
            }
            if storage[key] == nil {
                if insertionOrder.count >= maxEntries, !insertionOrder.isEmpty {
                    evictOldest()
                }
                insertionOrder.append(key)
            } else {
                byteCount -= sizes.removeValue(forKey: key) ?? 0
            }
            storage[key] = newValue

            if let sizeOf {
                let size = sizeOf(key, newValue)
                sizes[key] = size
                byteCount += size
            }

            // Evict until under budget, but never evict the entry just written:
            // a value larger than the whole budget would otherwise make every
            // insert wipe the cache and still leave it over budget.
            if let maxBytes {
                while byteCount > maxBytes, insertionOrder.count > 1 {
                    evictOldest()
                }
            }
        }
    }

    private mutating func evictOldest() {
        guard !insertionOrder.isEmpty else { return }
        let oldest = insertionOrder.removeFirst()
        storage.removeValue(forKey: oldest)
        byteCount -= sizes.removeValue(forKey: oldest) ?? 0
    }

    mutating func removeAll() {
        storage.removeAll()
        insertionOrder.removeAll()
        sizes.removeAll()
        byteCount = 0
    }
}
