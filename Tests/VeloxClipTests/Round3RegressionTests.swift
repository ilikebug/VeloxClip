import XCTest
@testable import VeloxClip

/// Regression cover for the round-3 findings.
final class Round3RegressionTests: XCTestCase {

    // MARK: - Eraser session (unrecoverable erases)

    /// Cancelling a drag must close the eraser session. Leaving it armed meant
    /// an erase after a mid-drag Cmd+Z took no undo snapshot, so those
    /// annotations could never be recovered.
    @MainActor
    func testEraseAfterAMidDragUndoIsStillUndoable() {
        let state = EditorState()
        state.currentTool = .line
        for i in 1...3 {
            state.startDrawing(at: CGPoint(x: i * 10, y: i * 10))
            state.updateDrawing(to: CGPoint(x: i * 10 + 5, y: i * 10 + 5))
            state.finishDrawing()
        }
        XCTAssertEqual(state.elements.count, 3)

        state.currentTool = .eraser
        state.eraseElements(at: CGPoint(x: 10, y: 10), radius: 30)
        let afterFirstErase = state.elements.count
        XCTAssertLessThan(afterFirstErase, 3, "precondition: the first erase removed something")

        // Cmd+Z mid-drag, then keep erasing
        state.undo()
        let restored = state.elements.count
        state.eraseElements(at: CGPoint(x: 20, y: 20), radius: 30)
        let afterSecondErase = state.elements.count
        XCTAssertLessThan(afterSecondErase, restored, "precondition: the second erase removed something")

        state.undo()
        XCTAssertEqual(state.elements.count, restored,
                       "the erase performed after the mid-drag undo must itself be undoable")
    }

    // MARK: - Paste stack completion window

    /// The stack shows "done" for a second before restoring the pre-stack
    /// clipboard. A copy made in that window must cancel the restore.
    @MainActor
    func testACopyDuringTheCompletionWindowCancelsTheRestore() async throws {
        let writer = FakePasteboardWriter()
        let service = PasteStackService(
            writer: writer,
            permissionCheck: { true },
            installsKeyMonitor: false
        )

        service.toggleStaged(ClipboardItem(type: "text", content: "one"))
        await service.startIfStaged()
        service.noteObservedPaste()
        try await Task.sleep(nanoseconds: 250_000_000)

        // The user copies while the HUD still reads "done"
        writer.simulateExternalWrite()
        service.noteClipboardChange()

        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(writer.restoredCount, 0,
                       "a copy during the completion window must suppress the restore")
    }

    // MARK: - Paste target liveness

    /// A remembered app that quit must not poison the lookup — the live
    /// frontmost app is right there.
    func testDeadRememberedAppFallsBackToTheLiveFrontmostApp() {
        let target = WindowTargetPolicy.pasteTargetProcessID(
            rememberedTargetProcessID: 999,
            currentFrontmostProcessID: 300,
            ownProcessID: 1,
            isAlive: { $0 != 999 }
        )
        XCTAssertEqual(target, 300, "a dead remembered PID must fall through")
    }

    func testLiveRememberedAppStillWins() {
        let target = WindowTargetPolicy.pasteTargetProcessID(
            rememberedTargetProcessID: 200,
            currentFrontmostProcessID: 300,
            ownProcessID: 1,
            isAlive: { _ in true }
        )
        XCTAssertEqual(target, 200, "a live remembered app is still preferred")
    }

    func testOwnProcessIsNeverATarget() {
        let target = WindowTargetPolicy.pasteTargetProcessID(
            rememberedTargetProcessID: 1,
            currentFrontmostProcessID: 1,
            ownProcessID: 1,
            isAlive: { _ in true }
        )
        XCTAssertNil(target)
    }

    // MARK: - Stored count

    /// The menu bar's History card sits beside a separate Favorites card, and
    /// the history limit counts only non-favorites — so the count must too, or
    /// favorites are reported twice.
    func testStoredCountExcludesFavorites() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        for i in 0..<7 {
            try await db.insertClipboardItem(ClipboardItem(type: "text", content: "plain \(i)"))
        }
        for i in 0..<3 {
            var fav = ClipboardItem(type: "text", content: "fav \(i)")
            fav.isFavorite = true
            fav.favoritedAt = Date()
            try await db.insertClipboardItem(fav)
        }

        let count = try await db.countStoredItems()
        XCTAssertEqual(count, 7, "the History card must not double-count favorites")
    }

    /// The dashboard guards with max(stored, loaded), which can repair an
    /// under-count but never an over-count — so deletions must refresh it.
    @MainActor
    func testStoredCountIsRefreshedAfterDeleting() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: false)

        var created: [ClipboardItem] = []
        for i in 0..<10 {
            let item = ClipboardItem(type: "text", content: "item \(i)")
            try await db.insertClipboardItem(item)
            created.append(item)
        }
        store.items = created
        await store.refreshStoredCount()
        XCTAssertEqual(store.storedItemCount, 10)

        await store.deleteItems(at: IndexSet(0..<6), in: created)

        XCTAssertEqual(store.storedItemCount, 4,
                       "the menu bar must not keep reporting the pre-delete count")
    }
}
