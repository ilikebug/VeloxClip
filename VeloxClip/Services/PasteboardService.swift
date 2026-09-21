import AppKit

/// Everything the app reads or writes on the system pasteboard.
///
/// Before this existed, six services touched `NSPasteboard.general` directly and
/// each had to remember a three-step protocol by hand:
///   1. clearContents + write
///   2. record the self-write, or `ClipboardMonitor` re-ingests our own write
///      as a brand-new history item
///   3. tell `PasteStackService`, or an active stack keeps advancing over a
///      clipboard someone else changed
/// Nothing enforced it. `TextCaptureService` hand-rolled all three inline and
/// `ScreenshotEditorService` skipped steps 2 and 3 entirely. Reads diverged too:
/// the monitor preferred PNG over TIFF while `PasteImageService` and
/// `ScreenshotService` preferred TIFF over PNG, so the same screenshot could be
/// stored as normalized PNG and displayed from uncompressed TIFF.
///
/// This type is the only place in the app allowed to name `NSPasteboard.general`.
/// Writing through it performs all three steps as one call.
@MainActor
final class PasteboardService {
    static let shared = PasteboardService()

    private let pasteboard: NSPasteboard
    private(set) var lastSelfWriteChangeCount: Int = -1

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    // MARK: - Self-write tracking

    /// True when `changeCount` identifies a write this app made.
    func isSelfWrite(changeCount: Int) -> Bool {
        changeCount == lastSelfWriteChangeCount
    }

    private func recordSelfWrite() {
        lastSelfWriteChangeCount = pasteboard.changeCount
    }

    // MARK: - Writing

    /// Clear + write a plain string + record the self-write. Every "copy X"
    /// button goes through here.
    func write(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        recordSelfWrite()
    }

    /// Writes file URLs so pasting into Finder reproduces the files, falling
    /// back to the plain path when the file no longer exists.
    func write(filePath: String, exists: Bool) {
        pasteboard.clearContents()
        defer { recordSelfWrite() }
        if exists, pasteboard.writeObjects([URL(fileURLWithPath: filePath) as NSURL]) {
            return
        }
        pasteboard.setString(filePath, forType: .string)
    }

    /// Writes a PNG blob as both image and PNG representations.
    func write(imageData: Data) {
        guard let image = NSImage(data: imageData) else {
            print("❌ Failed to create NSImage from data")
            return
        }
        pasteboard.clearContents()
        Self.writeImage(image, encoded: imageData, to: pasteboard)
        recordSelfWrite()
    }

    /// Writes an image WITHOUT marking it as a self-write, so `ClipboardMonitor`
    /// ingests it as new history. Used by the screenshot editor: an edited
    /// screenshot is genuinely new content, not the app echoing itself back.
    func writeAsNewContent(image: NSImage) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        if let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
    }

    /// Writes a history item in its native representation.
    ///
    /// Moved here from `ClipboardItem`, which had to `import AppKit` and call
    /// into `RowPresentation` — a domain entity depending on presentation code.
    @discardableResult
    func write(item: ClipboardItem) -> Bool {
        guard item.hasPasteablePayload else { return false }

        // Decode before clearing: a blob NSImage can't decode must leave the
        // user's clipboard intact, not empty (which the paste stack would then
        // record as its own successful write and silently skip the item)
        var decodedImage: NSImage?
        if item.type == "image" {
            guard let blob = item.data, let nsImage = NSImage(data: blob) else {
                print("❌ Failed to create NSImage from data")
                return false
            }
            decodedImage = nsImage
        }

        pasteboard.clearContents()
        defer { recordSelfWrite() }

        if let decodedImage, let blob = item.data {
            Self.writeImage(decodedImage, encoded: blob, to: pasteboard)
            return true
        }

        if item.type == "color", let content = item.content {
            pasteboard.setString(content, forType: .string)
            return true
        }

        if item.type == "file", let content = item.content {
            // Write real file URLs so pasting into Finder reproduces the files;
            // fall back to the plain paths if none of them still exist
            let urls = ClipboardItem.filePaths(from: content)
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty, pasteboard.writeObjects(urls) {
                return true
            }
            pasteboard.setString(content, forType: .string)
            return true
        }

        if let content = item.content {
            pasteboard.setString(content, forType: .string)
            return true
        }

        if let blob = item.data, item.type == "rtf" {
            pasteboard.setData(blob, forType: .rtf)
            return true
        }

        return false
    }

    /// Writes the NSImage object (consumers get TIFF on demand) plus the encoded
    /// bytes as an explicit representation. Stored blobs are PNG (normalized on
    /// ingest) and go out byte-for-byte — an earlier path re-encoded a full
    /// TIFF twice and a PNG once per paste, on the main thread.
    private static func writeImage(_ image: NSImage, encoded: Data, to pasteboard: NSPasteboard) {
        pasteboard.writeObjects([image])   // TIFF promise for every consumer
        if encoded.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            pasteboard.setData(encoded, forType: .png)
        } else if let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            // Legacy JPEG/TIFF blobs: one PNG encode (never declare foreign bytes as TIFF)
            pasteboard.setData(png, forType: .png)
        }
    }

    // MARK: - Reading

    /// The canonical type-priority order: file → text → rtf → png → tiff.
    ///
    /// Files come FIRST because Finder also puts the file name on the pasteboard
    /// as plain text; checking text first shadowed every file copy and recorded
    /// it as a text item. PNG beats TIFF because pasteboard TIFF is uncompressed
    /// (tens of MB per screenshot) — this used to be the opposite way round in
    /// half the call sites.
    ///
    /// Each `data(forType:)` copies the whole blob, so types are read lazily:
    /// never touch the multi-MB image types when text already matched.
    func read() -> PasteboardPayload {
        // fileURLsOnly: a copied browser URL must not be mistaken for a file
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        let hasFiles = !(fileURLs?.isEmpty ?? true)

        let text = hasFiles ? nil : pasteboard.string(forType: .string)
        let rtf = (hasFiles || text != nil) ? nil : pasteboard.data(forType: .rtf)
        let png = (hasFiles || text != nil || rtf != nil) ? nil : pasteboard.data(forType: .png)
        let tiff = (hasFiles || text != nil || rtf != nil || png != nil) ? nil : pasteboard.data(forType: .tiff)

        return PasteboardPayload(
            filePaths: hasFiles ? fileURLs?.map(\.path).joined(separator: "\n") : nil,
            text: text,
            rtf: rtf,
            image: png ?? tiff,
            sourceApp: nil
        )
    }

    /// Raw image bytes currently on the pasteboard, PNG preferred over TIFF.
    func readImageData() -> Data? {
        pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
    }

    var types: [NSPasteboard.PasteboardType]? { pasteboard.types }

    // MARK: - Snapshots

    func capture() -> PasteboardSnapshot? {
        PasteboardSnapshot.capture(from: pasteboard)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        snapshot.restore(to: pasteboard)
        recordSelfWrite()
    }
}
