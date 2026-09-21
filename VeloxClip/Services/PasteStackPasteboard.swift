import AppKit

// Raw byte-level snapshot of every pasteboard item, used to put the user's
// pre-stack clipboard back when the stack finishes. Finder writes one item per
// copied file, so restoring only the first turned a 3-file copy into one file.
struct PasteboardSnapshot {
    typealias TypedData = [(type: NSPasteboard.PasteboardType, data: Data)]
    let items: [TypedData]

    init(items: [TypedData]) { self.items = items }
    init(typedData: TypedData) { self.items = [typedData] }

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        let items: [TypedData] = (pasteboard.pasteboardItems ?? []).compactMap { item in
            let typedData = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return typedData.isEmpty ? nil : typedData
        }
        guard !items.isEmpty else { return nil }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        let pasteboardItems = items.map { typedData in
            let item = NSPasteboardItem()
            for (type, data) in typedData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems)
        // The self-write is recorded by PasteboardService.restore(_:)
    }
}

// Seam between the PasteStack state machine and the real pasteboard,
// so the state machine is unit-testable with a fake.
@MainActor
protocol PasteboardWriting {
    var changeCount: Int { get }
    func write(_ item: ClipboardItem)
    func capture() -> PasteboardSnapshot?
    func restore(_ snapshot: PasteboardSnapshot)
}

@MainActor
final class SystemPasteboardWriter: PasteboardWriting {
    var changeCount: Int { PasteboardService.shared.changeCount }

    func write(_ item: ClipboardItem) {
        // PasteboardService records the self-write for us
        PasteboardService.shared.write(item: item)
    }

    func capture() -> PasteboardSnapshot? {
        PasteboardService.shared.capture()
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        PasteboardService.shared.restore(snapshot)
    }
}
