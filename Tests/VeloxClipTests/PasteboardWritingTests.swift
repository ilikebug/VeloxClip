import XCTest
import AppKit
@testable import VeloxClip

@MainActor
final class PasteboardWritingTests: XCTestCase {
    private func makeTestPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("velox-test-\(UUID().uuidString)"))
    }

    func testImageCopyWritesStoredPNGBytesDirectly() {
        let pb = makeTestPasteboard()
        let png = TestSupport.makePNG(width: 3, height: 2)
        let item = ClipboardItem(type: "image", data: png)

        item.copyToPasteboard(pb)

        // The stored blob is already PNG (normalized on ingest) — it must land
        // byte-for-byte, not be round-tripped through TIFF twice
        XCTAssertEqual(pb.data(forType: .png), png)
        XCTAssertNotNil(pb.data(forType: .tiff))
    }

    func testImageItemWithoutPayloadLeavesPasteboardUntouched() {
        let pb = makeTestPasteboard()
        pb.clearContents()
        pb.setString("keep me", forType: .string)
        var ghost = ClipboardItem(type: "image", data: TestSupport.makePNG(width: 1, height: 1))
        ghost.content = "ocr text"   // an OCR'd screenshot carries text too
        ghost.data = nil             // …but its blob was deleted after the row was selected

        XCTAssertFalse(ghost.hasPasteablePayload)
        ghost.copyToPasteboard(pb)

        XCTAssertEqual(pb.string(forType: .string), "keep me", "a ghost paste used to wipe the clipboard (or paste the OCR text)")
    }

    func testUndecodableImageBlobLeavesPasteboardUntouched() {
        let pb = makeTestPasteboard()
        pb.clearContents()
        pb.setString("keep me", forType: .string)
        let corrupt = ClipboardItem(type: "image", data: Data([1, 2, 3, 4]))

        corrupt.copyToPasteboard(pb)

        // Clearing before the decode left an empty pasteboard that the paste stack
        // then treated as its own successful write
        XCTAssertEqual(pb.string(forType: .string), "keep me")
    }

    func testGateWriteClearsAndSetsString() {
        let pb = makeTestPasteboard()
        pb.setString("old", forType: .string)

        PasteboardSelfWriteGate.shared.write("#0A84FF", to: pb)

        XCTAssertEqual(pb.string(forType: .string), "#0A84FF")
        // The self-write mark is only meaningful for the general pasteboard, which
        // tests never touch — so it is not asserted here
    }

    func testSnapshotRestoresEveryPasteboardItem() {
        let pb = makeTestPasteboard()
        pb.clearContents()
        let a = NSPasteboardItem(); a.setString("first", forType: .string)
        let b = NSPasteboardItem(); b.setString("second", forType: .string)
        pb.writeObjects([a, b])

        let snapshot = PasteboardSnapshot.capture(from: pb)
        pb.clearContents()
        pb.setString("queue item", forType: .string)
        snapshot?.restore(to: pb)

        // Finder puts one item per copied file — restoring only the first would
        // turn a 3-file copy into a 1-file paste
        XCTAssertEqual(pb.pasteboardItems?.count, 2)
        XCTAssertEqual(pb.pasteboardItems?.compactMap { $0.string(forType: .string) }, ["first", "second"])
    }
}
