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

@MainActor
final class FakePasteboardWriter: PasteboardWriting {
    private(set) var changeCount = 0
    private(set) var written: [ClipboardItem] = []
    private(set) var restoredCount = 0
    var snapshotToCapture: PasteboardSnapshot? =
        PasteboardSnapshot(typedData: [(.string, Data("before".utf8))])

    func write(_ item: ClipboardItem) {
        written.append(item)
        changeCount += 1
    }
    func capture() -> PasteboardSnapshot? { snapshotToCapture }
    func restore(_ snapshot: PasteboardSnapshot) {
        restoredCount += 1
        changeCount += 1
    }
    func simulateExternalWrite() { changeCount += 1 }
}

@MainActor
final class PasteStackServiceTests: XCTestCase {
    private var writer: FakePasteboardWriter!
    private var service: PasteStackService!

    override func setUp() async throws {
        writer = FakePasteboardWriter()
        service = PasteStackService(
            writer: writer,
            permissionCheck: { true },
            installsKeyMonitor: false
        )
    }

    private func makeItems(_ count: Int) -> [ClipboardItem] {
        (0..<count).map { ClipboardItem(type: "text", content: "item-\($0)") }
    }

    func testToggleStagedAddsAndRemovesInOrder() {
        let items = makeItems(3)
        items.forEach { service.toggleStaged($0) }
        XCTAssertEqual(service.staged.map(\.id), items.map(\.id))
        XCTAssertEqual(service.stagedIndex(of: items[1].id), 1)

        service.toggleStaged(items[0])
        XCTAssertEqual(service.staged.map(\.id), [items[1].id, items[2].id])
        XCTAssertEqual(service.stagedIndex(of: items[1].id), 0)
        XCTAssertNil(service.stagedIndex(of: items[0].id))
    }

    func testClearStagedOnlyWhileIdle() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }

        service.clearStaged()
        XCTAssertTrue(service.staged.isEmpty)

        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()
        service.clearStaged()

        XCTAssertEqual(service.phase, .active)
        XCTAssertEqual(service.queue.map(\.id), items.map(\.id))
    }

    func testStartWritesFirstItemAndActivates() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }

        await service.startIfStaged()

        XCTAssertEqual(service.phase, .active)
        XCTAssertTrue(service.staged.isEmpty)
        XCTAssertEqual(service.queue.count, 2)
        XCTAssertEqual(service.cursor, 0)
        XCTAssertEqual(writer.written.map(\.content), ["item-0"])
    }

    func testStartWithNothingStagedDoesNothing() async {
        await service.startIfStaged()
        XCTAssertEqual(service.phase, .idle)
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testStartWithoutPermissionStaysIdleAndKeepsStaging() async {
        let denied = PasteStackService(
            writer: writer, permissionCheck: { false }, installsKeyMonitor: false)
        denied.toggleStaged(makeItems(1)[0])

        await denied.startIfStaged()

        // Staging survives so granting permission + closing the overlay retries
        XCTAssertEqual(denied.phase, .idle)
        XCTAssertEqual(denied.staged.count, 1)
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testObservedPasteAdvancesAndWritesNext() async {
        let items = makeItems(3)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        service.advanceAfterObservedPaste()

        XCTAssertEqual(service.cursor, 1)
        XCTAssertEqual(service.phase, .active)
        XCTAssertEqual(writer.written.map(\.content), ["item-0", "item-1"])
    }

    func testObservedPasteOnLastItemCompletes() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        service.advanceAfterObservedPaste()
        service.advanceAfterObservedPaste()

        XCTAssertEqual(service.phase, .completed)
        // cursor stays on the last item so HUD shows n/n
        XCTAssertEqual(service.cursor, 1)
    }

    func testFinalizeCompletionRestoresSnapshotAndGoesIdle() async {
        let items = makeItems(1)
        service.toggleStaged(items[0])
        await service.startIfStaged()
        service.advanceAfterObservedPaste()
        XCTAssertEqual(service.phase, .completed)

        service.finalizeCompletion()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(writer.restoredCount, 1)
    }

    func testChangeCountMismatchPausesInsteadOfAdvancing() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        writer.simulateExternalWrite()
        service.advanceAfterObservedPaste()

        XCTAssertEqual(service.phase, .paused)
        XCTAssertEqual(service.cursor, 0)
        XCTAssertEqual(writer.written.count, 1)
    }

    func testForeignWritePausesAndResumeRewritesCurrent() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        writer.simulateExternalWrite()
        service.noteClipboardChange()
        XCTAssertEqual(service.phase, .paused)

        service.resume()
        XCTAssertEqual(service.phase, .active)
        XCTAssertEqual(writer.written.map(\.content), ["item-0", "item-0"])
    }

    func testOwnWriteDoesNotPause() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        // changeCount still matches the stack's own write — no pause
        service.noteClipboardChange()
        XCTAssertEqual(service.phase, .active)
    }

    func testNoRestoreWhenUserWroteDuringStack() async {
        let items = makeItems(1)
        service.toggleStaged(items[0])
        await service.startIfStaged()

        writer.simulateExternalWrite()
        service.noteClipboardChange()
        service.resume()
        service.advanceAfterObservedPaste()
        service.finalizeCompletion()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(writer.restoredCount, 0)
    }

    func testCancelRestoresAndGoesIdle() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        service.cancel()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(writer.restoredCount, 1)
        XCTAssertTrue(service.queue.isEmpty)
    }

    func testStartDropsBlobItemsWhoseDataIsGone() async {
        // An image staged then deleted from history has no blob to load —
        // it must be dropped instead of silently re-pasting the previous item
        let ghost = ClipboardItem(type: "image", content: nil, data: nil)
        let text = ClipboardItem(type: "text", content: "still here")
        service.toggleStaged(ghost)
        service.toggleStaged(text)

        await service.startIfStaged()

        XCTAssertEqual(service.phase, .active)
        XCTAssertEqual(service.queue.map(\.content), ["still here"])
    }

    func testStartWithOnlyGhostItemsStaysIdle() async {
        let ghost = ClipboardItem(type: "image", content: nil, data: nil)
        service.toggleStaged(ghost)

        await service.startIfStaged()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testStagingIgnoredWhileActive() async {
        let items = makeItems(2)
        service.toggleStaged(items[0])
        await service.startIfStaged()

        service.toggleStaged(items[1])
        XCTAssertTrue(service.staged.isEmpty)
    }
}
