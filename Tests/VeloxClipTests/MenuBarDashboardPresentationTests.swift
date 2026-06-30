import XCTest
@testable import VeloxClip

final class MenuBarDashboardPresentationTests: XCTestCase {
    func testIdleDashboardShowsHistoryFavoriteAndStagedCounts() {
        let presentation = MenuBarDashboardPresentation(
            historyCount: 128,
            favoriteCount: 3,
            stagedCount: 2,
            queueCount: 0,
            cursor: 0,
            phase: .idle
        )

        XCTAssertEqual(presentation.historyValue, "128")
        XCTAssertEqual(presentation.favoriteValue, "3")
        XCTAssertEqual(presentation.queueValue, "2")
        XCTAssertEqual(presentation.statusText, "已暂存 2 项")
    }

    func testActiveDashboardShowsQueueProgress() {
        let presentation = MenuBarDashboardPresentation(
            historyCount: 128,
            favoriteCount: 3,
            stagedCount: 0,
            queueCount: 4,
            cursor: 1,
            phase: .active
        )

        XCTAssertEqual(presentation.queueValue, "2/4")
        XCTAssertEqual(presentation.statusText, "Paste Stack 进行中")
    }

    func testPausedDashboardShowsPausedProgress() {
        let presentation = MenuBarDashboardPresentation(
            historyCount: 128,
            favoriteCount: 3,
            stagedCount: 0,
            queueCount: 4,
            cursor: 2,
            phase: .paused
        )

        XCTAssertEqual(presentation.queueValue, "3/4")
        XCTAssertEqual(presentation.statusText, "Paste Stack 已暂停")
    }

    func testDashboardDoesNotExposeConfigurableShortcutDefaults() {
        let presentation = MenuBarDashboardPresentation(
            historyCount: 0,
            favoriteCount: 0,
            stagedCount: 0,
            queueCount: 0,
            cursor: 0,
            phase: .idle
        )

        XCTAssertNil(presentation.footerShortcutHint)
    }

    func testDashboardActionsThatLeaveMenuContextDismissThePanel() {
        XCTAssertTrue(MenuBarDashboardAction.openClipboard.dismissesPanel)
        XCTAssertTrue(MenuBarDashboardAction.pasteImage.dismissesPanel)
        XCTAssertTrue(MenuBarDashboardAction.captureText.dismissesPanel)
        XCTAssertTrue(MenuBarDashboardAction.settings.dismissesPanel)
        XCTAssertTrue(MenuBarDashboardAction.startQueue.dismissesPanel)
        XCTAssertTrue(MenuBarDashboardAction.resumeQueue.dismissesPanel)
        XCTAssertTrue(MenuBarDashboardAction.cancelQueue.dismissesPanel)
    }

    func testDashboardClearQueueStaysInPanel() {
        XCTAssertFalse(MenuBarDashboardAction.clearQueue.dismissesPanel)
    }

    func testQueueActionsHideAppAfterActionToReturnFocus() {
        XCTAssertTrue(MenuBarDashboardAction.startQueue.hidesAppAfterAction)
        XCTAssertTrue(MenuBarDashboardAction.resumeQueue.hidesAppAfterAction)
        XCTAssertTrue(MenuBarDashboardAction.cancelQueue.hidesAppAfterAction)
    }

    func testWindowOpeningActionsDoNotHideAppAfterAction() {
        XCTAssertFalse(MenuBarDashboardAction.openClipboard.hidesAppAfterAction)
        XCTAssertFalse(MenuBarDashboardAction.pasteImage.hidesAppAfterAction)
        XCTAssertFalse(MenuBarDashboardAction.captureText.hidesAppAfterAction)
        XCTAssertFalse(MenuBarDashboardAction.settings.hidesAppAfterAction)
    }
}
