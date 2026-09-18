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
    private(set) var capturedCount = 0

    func write(_ item: ClipboardItem) {
        written.append(item)
        changeCount += 1
    }
    func capture() -> PasteboardSnapshot? {
        capturedCount += 1
        return snapshotToCapture
    }
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

    // MARK: Observed-paste coalescing

    func testRapidDoubleCommandVAdvancesOnlyOnce() async throws {
        for item in makeItems(3) { service.toggleStaged(item) }
        await service.startIfStaged()

        // Two Cmd+V key events inside the settle delay (a "double paste")
        service.noteObservedPaste()
        service.noteObservedPaste()
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(service.cursor, 1, "second key event must coalesce into the pending advance")
        XCTAssertEqual(service.phase, .active)
    }

    func testStagedItemsAreKeptWhenEveryItemTurnsOutToBeAGhost() async {
        // Blob deleted from history after staging: nothing can be pasted, so the
        // stack must not start — and must not silently throw the staging away
        var ghost = ClipboardItem(type: "image", data: Data([1, 2, 3]))
        ghost.data = nil
        service.toggleStaged(ghost)

        await service.startIfStaged()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(service.staged.count, 1)
    }

    func testConcurrentStartsDoNotRestartTheStack() async {
        // A blob load really suspends (DB actor hop), which is the window the
        // second caller used to slip through
        let slowLoader: @Sendable (UUID) async -> Data? = { _ in
            try? await Task.sleep(nanoseconds: 20_000_000)
            return Data([1, 2, 3])
        }
        service = PasteStackService(
            writer: writer,
            permissionCheck: { true },
            loadBlob: slowLoader,
            installsKeyMonitor: false
        )
        for index in 0..<3 {
            var image = ClipboardItem(type: "image", data: Data([UInt8(index)]))
            image.data = nil   // lazy-loaded, like a list item
            service.toggleStaged(image)
        }

        // Two hideOverlay paths can fire in one runloop turn; the second must not
        // re-capture the snapshot (over the stack's own write) or reset the cursor
        let firstStart = Task { @MainActor [service] in await service!.startIfStaged() }
        let secondStart = Task { @MainActor [service] in await service!.startIfStaged() }
        await firstStart.value
        await secondStart.value

        XCTAssertEqual(service.phase, .active)
        XCTAssertEqual(service.queue.count, 3)
        XCTAssertEqual(writer.written.count, 1, "the stack must be written exactly once")
        XCTAssertEqual(writer.capturedCount, 1, "a second capture would snapshot our own write")
    }

    func testMissingAccessibilityPromptsOnlyOnce() async {
        var promptCount = 0
        let denied = PasteStackService(
            writer: writer,
            permissionCheck: { promptCount += 1; return false },
            quietPermissionCheck: { false },
            installsKeyMonitor: false
        )
        denied.toggleStaged(makeItems(1)[0])

        await denied.startIfStaged()
        await denied.startIfStaged()
        await denied.startIfStaged()

        XCTAssertEqual(promptCount, 1, "every overlay close re-triggered the system dialog")
        XCTAssertEqual(denied.staged.count, 1, "staged items are kept for when permission is granted")
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
