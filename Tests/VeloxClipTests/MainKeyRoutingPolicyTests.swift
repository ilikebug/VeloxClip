import XCTest
@testable import VeloxClip

final class MainKeyRoutingPolicyTests: XCTestCase {
    func testSpaceNeverStages() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldStageOnSpace(
            isComposingText: false
        ))
    }

    func testSpaceStillDoesNotStageWhileInputMethodIsComposing() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldStageOnSpace(
            isComposingText: true
        ))
    }

    func testCommandReturnStagesWhenInputMethodIsNotComposing() {
        XCTAssertTrue(MainKeyRoutingPolicy.shouldStageOnCommandReturn(
            isComposingText: false
        ))
    }

    func testCommandReturnDoesNotStageWhileInputMethodIsComposing() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldStageOnCommandReturn(
            isComposingText: true
        ))
    }

    func testPlainRightArrowDoesNotOpenDetail() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldOpenDetailOnRightArrow(
            isCommandPressed: false,
            isComposingText: false
        ))
    }

    func testCommandRightArrowOpensDetailWhenInputMethodIsNotComposing() {
        XCTAssertTrue(MainKeyRoutingPolicy.shouldOpenDetailOnRightArrow(
            isCommandPressed: true,
            isComposingText: false
        ))
    }

    func testCommandRightArrowDoesNotOpenDetailWhileInputMethodIsComposing() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldOpenDetailOnRightArrow(
            isCommandPressed: true,
            isComposingText: true
        ))
    }

    func testReturnPastesWhenInputMethodIsNotComposing() {
        XCTAssertTrue(MainKeyRoutingPolicy.shouldPasteOnReturn(
            isCommandPressed: false,
            isComposingText: false
        ))
    }

    func testReturnDoesNotPasteWhileInputMethodIsComposing() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldPasteOnReturn(
            isCommandPressed: false,
            isComposingText: true
        ))
    }

    func testReturnDoesNotPasteWhenCommandIsPressed() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldPasteOnReturn(
            isCommandPressed: true,
            isComposingText: false
        ))
    }

    func testEscapeClearsOrClosesWhenInputMethodIsNotComposing() {
        XCTAssertTrue(MainKeyRoutingPolicy.shouldHandleEscape(isComposingText: false))
    }

    func testEscapeDoesNotClearOrCloseWhileInputMethodIsComposing() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldHandleEscape(isComposingText: true))
    }

    func testTabSwitchesTabsWhenInputMethodIsNotComposing() {
        XCTAssertTrue(MainKeyRoutingPolicy.shouldSwitchTabsOnTab(isComposingText: false))
    }

    func testTabDoesNotSwitchTabsWhileInputMethodIsComposing() {
        XCTAssertFalse(MainKeyRoutingPolicy.shouldSwitchTabsOnTab(isComposingText: true))
    }

    func testListInteractionKeepsSearchFocused() {
        XCTAssertFalse(MainFocusRoutingPolicy.shouldBlurSearchOnListInteraction(hasSelectableItems: true))
    }

    func testRestoresSearchFocusAfterListSelectionWhenListIsVisible() {
        XCTAssertTrue(MainFocusRoutingPolicy.shouldRestoreSearchFocus(
            isDetailPresented: false,
            isCommandPalettePresented: false
        ))
    }

    func testRestoresSearchFocusAfterRowControlInteraction() {
        XCTAssertTrue(MainFocusRoutingPolicy.shouldRestoreSearchFocusAfterListInteraction(.rowControl))
    }

    func testRestoresSearchFocusAfterRowSelection() {
        XCTAssertTrue(MainFocusRoutingPolicy.shouldRestoreSearchFocusAfterListInteraction(.rowSelection))
    }

    func testRestoresSearchFocusAfterKeyboardSelection() {
        XCTAssertTrue(MainFocusRoutingPolicy.shouldRestoreSearchFocusAfterListInteraction(.keyboardSelection))
    }

    func testClearsSearchFocusWhenOpeningDetail() {
        XCTAssertTrue(MainFocusRoutingPolicy.shouldClearSearchFocusWhenPresentingDetail())
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
