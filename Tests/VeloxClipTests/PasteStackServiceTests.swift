import XCTest
import AppKit
@testable import VeloxClip

final class PasteboardSnapshotTests: XCTestCase {
    // A uniquely named pasteboard isolates tests from the system clipboard
    private func makeTestPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("velox-test-\(UUID().uuidString)"))
    }

    @MainActor
    func testCaptureAndRestoreRoundTripsStringContent() {
        let pb = makeTestPasteboard()
        pb.clearContents()
        pb.setString("before stack", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pb)
        XCTAssertNotNil(snapshot)

        pb.clearContents()
        pb.setString("queue item", forType: .string)

        snapshot?.restore(to: pb)
        XCTAssertEqual(pb.string(forType: .string), "before stack")
    }

    @MainActor
    func testCaptureOfEmptyPasteboardReturnsNil() {
        let pb = makeTestPasteboard()
        pb.clearContents()
        XCTAssertNil(PasteboardSnapshot.capture(from: pb))
    }
}
