import XCTest
@testable import VeloxClip

/// Table-driven coverage of the overlay's key routing.
///
/// The predecessor suite tested four one-line boolean helpers while the 120-line
/// dispatch that actually decided behaviour stayed inline in MainView and
/// untested. These exercise the real routing table.
final class MainKeyRouterTests: XCTestCase {
    private func ctx(
        keyCode: UInt16 = 0,
        characters: String? = nil,
        command: Bool = false,
        overlayKey: Bool = true,
        palette: Bool = false,
        detail: Bool = false,
        editingText: Bool = false,
        hasTextSelection: Bool = false,
        composing: Bool = false,
        hasSelection: Bool = true,
        searchEmpty: Bool = true,
        visibleCount: Int = 5
    ) -> MainKeyContext {
        MainKeyContext(
            keyCode: keyCode,
            characters: characters,
            isCommandPressed: command,
            isOverlayKeyWindow: overlayKey,
            isPalettePresented: palette,
            isDetailPresented: detail,
            isEditingText: editingText,
            hasTextSelection: hasTextSelection,
            isComposingText: composing,
            hasSelection: hasSelection,
            isSearchTextEmpty: searchEmpty,
            visibleItemCount: visibleCount
        )
    }

    // MARK: - Window and palette gating

    func testKeysAreIgnoredWhenTheOverlayIsNotTheKeyWindow() {
        // Otherwise the overlay would hijack keys from Settings and other windows
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.escape, overlayKey: false)), .passThrough)
    }

    func testPaletteHandlesItsOwnKeys() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.downArrow, palette: true)), .passThrough)
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.escape, palette: true)), .passThrough)
    }

    // MARK: - IME composition
    // Never steal a key mid-composition: the IME owns arrows, return and escape
    // while a candidate window is open.

    func testCompositionKeepsEveryStealableKey() {
        for key in [MainKeyRouter.upArrow, MainKeyRouter.downArrow, MainKeyRouter.returnKey,
                    MainKeyRouter.keypadEnter, MainKeyRouter.escape, MainKeyRouter.tab] {
            XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: key, composing: true)), .passThrough,
                           "key \(key) must fall through while the IME is composing")
        }
    }

    func testCompositionBlocksCommandReturnStaging() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(keyCode: MainKeyRouter.returnKey, command: true, composing: true)),
            .passThrough
        )
    }

    func testCompositionBlocksCommandRightArrow() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(keyCode: MainKeyRouter.rightArrow, command: true, composing: true)),
            .passThrough
        )
    }

    // MARK: - ⌘C

    /// In list mode the search field is the permanent first responder, so
    /// honoring "is editing text" blindly would route ⌘C to the empty search
    /// field instead of copying the selected item.
    func testCommandCCopiesTheItemWhenTheFocusedFieldHasNoSelection() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(characters: "c", command: true, editingText: true, hasTextSelection: false)),
            .copySelection
        )
    }

    func testCommandCYieldsToNativeCopyWhenTextIsSelected() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(characters: "c", command: true, editingText: true, hasTextSelection: true)),
            .passThrough
        )
    }

    func testCommandCDoesNothingWithoutASelectedItem() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(characters: "c", command: true, hasSelection: false)),
            .passThrough
        )
    }

    // MARK: - List mode

    func testArrowsMoveSelection() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.upArrow)), .moveSelection(by: -1))
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.downArrow)), .moveSelection(by: 1))
    }

    func testReturnPastesAndKeypadEnterBehavesIdentically() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.returnKey)), .pasteSelection)
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.keypadEnter)), .pasteSelection)
    }

    func testCommandReturnStagesInsteadOfPasting() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(keyCode: MainKeyRouter.returnKey, command: true)),
            .stageSelection
        )
    }

    func testCommandReturnWithoutASelectionFallsThrough() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(keyCode: MainKeyRouter.returnKey, command: true, hasSelection: false)),
            .passThrough
        )
    }

    /// Plain → belongs to the search field's caret; only ⌘→ opens detail.
    func testOnlyCommandRightArrowOpensDetail() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.rightArrow)), .passThrough)
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.rightArrow, command: true)), .openDetail)
    }

    func testCommandRightArrowWithoutASelectionFallsThrough() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(keyCode: MainKeyRouter.rightArrow, command: true, hasSelection: false)),
            .passThrough
        )
    }

    /// Esc clears a non-empty query first, and only closes the overlay once the
    /// query is already empty.
    func testEscapeClearsTheQueryBeforeClosingTheOverlay() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.escape, searchEmpty: false)), .clearSearch)
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.escape, searchEmpty: true)), .closeOverlay)
    }

    func testTabSwitchesTabs() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.tab)), .switchTab)
    }

    func testSpaceAlwaysBelongsToTextInput() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.space)), .passThrough)
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.space, command: true)), .passThrough)
    }

    func testPlainTypingFallsThroughToTheFocusedField() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: 0, characters: "a")), .passThrough)
    }

    // MARK: - ⌘1–9

    func testCommandDigitPastesTheNthVisibleRow() {
        XCTAssertEqual(MainKeyRouter.route(ctx(characters: "1", command: true)), .pasteRow(index: 0))
        XCTAssertEqual(MainKeyRouter.route(ctx(characters: "5", command: true)), .pasteRow(index: 4))
    }

    func testCommandDigitBeyondTheVisibleRowsFallsThrough() {
        XCTAssertEqual(
            MainKeyRouter.route(ctx(characters: "9", command: true, visibleCount: 3)),
            .passThrough
        )
    }

    func testPlainDigitIsTypedNotRouted() {
        XCTAssertEqual(MainKeyRouter.route(ctx(characters: "1")), .passThrough)
    }

    // MARK: - Detail mode

    func testDetailModeYieldsEveryKeyWhileEditingText() {
        // Otherwise adding a tag or selecting preview text is impossible
        for key in [MainKeyRouter.escape, MainKeyRouter.returnKey, MainKeyRouter.upArrow] {
            XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: key, detail: true, editingText: true)), .passThrough)
        }
    }

    func testEscapeAndCommandLeftCloseDetail() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.escape, detail: true)), .closeDetail)
        XCTAssertEqual(
            MainKeyRouter.route(ctx(keyCode: MainKeyRouter.leftArrow, command: true, detail: true)),
            .closeDetail
        )
    }

    func testPlainLeftArrowDoesNotCloseDetail() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.leftArrow, detail: true)), .passThrough)
    }

    func testDetailReturnPastesAndCommandReturnStages() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.returnKey, detail: true)), .pasteSelection)
        XCTAssertEqual(
            MainKeyRouter.route(ctx(keyCode: MainKeyRouter.returnKey, command: true, detail: true)),
            .stageSelection
        )
    }

    func testDetailArrowsScrollThePaneRatherThanMovingSelection() {
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.upArrow, detail: true)), .passThrough)
        XCTAssertEqual(MainKeyRouter.route(ctx(keyCode: MainKeyRouter.downArrow, detail: true)), .passThrough)
    }

    func testCommandKOpensThePaletteInBothModes() {
        XCTAssertEqual(MainKeyRouter.route(ctx(characters: "k", command: true)), .openPalette)
        XCTAssertEqual(MainKeyRouter.route(ctx(characters: "k", command: true, detail: true)), .openPalette)
    }
}

final class MainFocusRoutingPolicyTests: XCTestCase {
    func testRestoresSearchFocusAfterListSelectionWhenListIsVisible() {
        XCTAssertTrue(MainFocusRoutingPolicy.shouldRestoreSearchFocus(
            isDetailPresented: false,
            isCommandPalettePresented: false
        ))
    }

    func testDoesNotRestoreSearchFocusWhileDetailIsPresented() {
        XCTAssertFalse(MainFocusRoutingPolicy.shouldRestoreSearchFocus(
            isDetailPresented: true,
            isCommandPalettePresented: false
        ))
    }

    func testDoesNotRestoreSearchFocusWhileCommandPaletteIsPresented() {
        XCTAssertFalse(MainFocusRoutingPolicy.shouldRestoreSearchFocus(
            isDetailPresented: false,
            isCommandPalettePresented: true
        ))
    }
}
