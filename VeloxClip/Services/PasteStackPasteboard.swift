import AppKit

// Raw byte-level snapshot of the pasteboard's first item, used to put the
// user's pre-stack clipboard back when the stack finishes.
struct PasteboardSnapshot {
    let typedData: [(type: NSPasteboard.PasteboardType, data: Data)]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        let typedData = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
            guard let data = item.data(forType: type) else { return nil }
            return (type, data)
        }
        guard !typedData.isEmpty else { return nil }
        return PasteboardSnapshot(typedData: typedData)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        for (type, data) in typedData {
            item.setData(data, forType: type)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        PasteboardSelfWriteGate.shared.recordSelfWrite()
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
    var changeCount: Int { NSPasteboard.general.changeCount }

    func write(_ item: ClipboardItem) {
        // copyToPasteboard already records the self-write in the gate
        item.copyToPasteboard()
    }

    func capture() -> PasteboardSnapshot? {
        PasteboardSnapshot.capture(from: NSPasteboard.general)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        snapshot.restore(to: NSPasteboard.general)
    }
}
