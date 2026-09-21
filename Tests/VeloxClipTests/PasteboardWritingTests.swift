import XCTest
import AppKit
@testable import VeloxClip

@MainActor
final class PasteboardWritingTests: XCTestCase {
    /// A uniquely-named pasteboard, so tests never touch the user's real one.
    private func makeService() -> (PasteboardService, NSPasteboard) {
        let pb = NSPasteboard(name: NSPasteboard.Name("velox-test-\(UUID().uuidString)"))
        return (PasteboardService(pasteboard: pb), pb)
    }

    func testImageCopyWritesStoredPNGBytesDirectly() {
        let (service, pb) = makeService()
        let png = TestSupport.makePNG(width: 3, height: 2)
        let item = ClipboardItem(type: "image", data: png)

        service.write(item: item)

        // The stored blob is already PNG (normalized on ingest) — it must land
        // byte-for-byte, not be round-tripped through TIFF twice
        XCTAssertEqual(pb.data(forType: .png), png)
        XCTAssertNotNil(pb.data(forType: .tiff))
    }

    func testImageItemWithoutPayloadLeavesPasteboardUntouched() {
        let (service, pb) = makeService()
        pb.clearContents()
        pb.setString("keep me", forType: .string)
        var ghost = ClipboardItem(type: "image", data: TestSupport.makePNG(width: 1, height: 1))
        ghost.content = "ocr text"   // an OCR'd screenshot carries text too
        ghost.data = nil             // …but its blob was deleted after the row was selected

        XCTAssertFalse(ghost.hasPasteablePayload)
        service.write(item: ghost)

        XCTAssertEqual(pb.string(forType: .string), "keep me", "a ghost paste used to wipe the clipboard (or paste the OCR text)")
    }

    func testUndecodableImageBlobLeavesPasteboardUntouched() {
        let (service, pb) = makeService()
        pb.clearContents()
        pb.setString("keep me", forType: .string)
        let corrupt = ClipboardItem(type: "image", data: Data([1, 2, 3, 4]))

        service.write(item: corrupt)

        // Clearing before the decode left an empty pasteboard that the paste stack
        // then treated as its own successful write
        XCTAssertEqual(pb.string(forType: .string), "keep me")
    }

    func testWriteTextClearsAndSetsString() {
        let (service, pb) = makeService()
        pb.setString("old", forType: .string)

        service.write(text: "#0A84FF")

        XCTAssertEqual(pb.string(forType: .string), "#0A84FF")
    }

    /// The three-step protocol (clear+write → record self-write → notify the
    /// stack) used to be hand-rolled at each call site, enforced only by
    /// comments. Forgetting step 2 made the monitor re-ingest the app's own
    /// write as a brand-new history item.
    func testEveryGatedWriteMarksItselfAsASelfWrite() {
        let (service, pb) = makeService()

        service.write(text: "copied")
        XCTAssertTrue(service.isSelfWrite(changeCount: pb.changeCount),
                      "a text write must be recognisable as our own")

        service.write(item: ClipboardItem(type: "text", content: "an item"))
        XCTAssertTrue(service.isSelfWrite(changeCount: pb.changeCount),
                      "an item write must be recognisable as our own")

        service.write(filePath: "/tmp/nonexistent-\(UUID().uuidString)", exists: false)
        XCTAssertTrue(service.isSelfWrite(changeCount: pb.changeCount),
                      "a file write must be recognisable as our own")
    }

    /// The screenshot editor deliberately opts out: an edited image is new
    /// content and SHOULD be ingested into history.
    func testEditedImageIsWrittenUngatedSoItEntersHistory() {
        let (service, pb) = makeService()
        let image = NSImage(data: TestSupport.makePNG(width: 2, height: 2))!

        service.writeAsNewContent(image: image)

        XCTAssertFalse(service.isSelfWrite(changeCount: pb.changeCount),
                       "an edited screenshot must NOT be gated, or it never reaches history")
        XCTAssertNotNil(pb.data(forType: .png))
    }

    func testReadAppliesTheCanonicalTypePriority() {
        let (service, pb) = makeService()

        // Text beats rtf and image
        pb.clearContents()
        pb.setString("plain", forType: .string)
        pb.setData(Data([0x7B]), forType: .rtf)
        var payload = service.read()
        XCTAssertEqual(payload.text, "plain")
        XCTAssertNil(payload.rtf, "rtf must not be read once text matched")

        // RTF beats image
        pb.clearContents()
        pb.setData(Data([0x7B, 0x5C]), forType: .rtf)
        pb.setData(TestSupport.makePNG(width: 1, height: 1), forType: .png)
        payload = service.read()
        XCTAssertNil(payload.text)
        XCTAssertEqual(payload.rtf, Data([0x7B, 0x5C]))
        XCTAssertNil(payload.image, "image must not be read once rtf matched")
    }

    func testReadImageDataPrefersPNGOverUncompressedTIFF() {
        let (service, pb) = makeService()
        let png = TestSupport.makePNG(width: 2, height: 2)
        pb.clearContents()
        pb.setData(Data([0x4D, 0x4D, 0x00, 0x2A]), forType: .tiff)
        pb.setData(png, forType: .png)

        // Half the call sites used to prefer TIFF here, so the same screenshot
        // could be stored as PNG and displayed from uncompressed TIFF
        XCTAssertEqual(service.readImageData(), png)
    }

    func testSnapshotRestoresEveryPasteboardItem() {
        let (service, pb) = makeService()
        pb.clearContents()
        let a = NSPasteboardItem(); a.setString("first", forType: .string)
        let b = NSPasteboardItem(); b.setString("second", forType: .string)
        pb.writeObjects([a, b])

        let snapshot = service.capture()
        pb.clearContents()
        pb.setString("queue item", forType: .string)
        if let snapshot { service.restore(snapshot) }

        // Finder puts one item per copied file — restoring only the first would
        // turn a 3-file copy into a 1-file paste
        XCTAssertEqual(pb.pasteboardItems?.count, 2)
        XCTAssertEqual(pb.pasteboardItems?.compactMap { $0.string(forType: .string) }, ["first", "second"])
        XCTAssertTrue(service.isSelfWrite(changeCount: pb.changeCount),
                      "restoring the user's clipboard must not look like a foreign write")
    }
}
