import XCTest
@testable import VeloxClip

final class WindowTargetPolicyTests: XCTestCase {
    func testRememberedTargetIgnoresSelfAndKeepsPreviousTarget() {
        XCTAssertEqual(
            WindowTargetPolicy.rememberedTargetProcessID(
                currentFrontmostProcessID: 42,
                previousTargetProcessID: 7,
                ownProcessID: 42
            ),
            7
        )
    }

    func testRememberedTargetDoesNotRecordSelfWhenNoPreviousTargetExists() {
        XCTAssertNil(
            WindowTargetPolicy.rememberedTargetProcessID(
                currentFrontmostProcessID: 42,
                previousTargetProcessID: nil,
                ownProcessID: 42
            )
        )
    }

    func testRememberedTargetRecordsNonSelfFrontmostApp() {
        XCTAssertEqual(
            WindowTargetPolicy.rememberedTargetProcessID(
                currentFrontmostProcessID: 12,
                previousTargetProcessID: 7,
                ownProcessID: 42
            ),
            12
        )
    }

    func testPasteTargetFallsBackToNonSelfFrontmostApp() {
        XCTAssertEqual(
            WindowTargetPolicy.pasteTargetProcessID(
                rememberedTargetProcessID: nil,
                currentFrontmostProcessID: 12,
                ownProcessID: 42
            ),
            12
        )
    }

    func testPasteTargetNeverUsesSelf() {
        XCTAssertNil(
            WindowTargetPolicy.pasteTargetProcessID(
                rememberedTargetProcessID: 42,
                currentFrontmostProcessID: 42,
                ownProcessID: 42
            )
        )
    }

    func testTracksActivatedAppsOnlyWhenTheyAreNotSelf() {
        XCTAssertTrue(WindowTargetPolicy.shouldRememberActivatedApp(
            activatedProcessID: 12,
            ownProcessID: 42
        ))
        XCTAssertFalse(WindowTargetPolicy.shouldRememberActivatedApp(
            activatedProcessID: 42,
            ownProcessID: 42
        ))
    }
}
