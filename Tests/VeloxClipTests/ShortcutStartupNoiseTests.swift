import XCTest
@testable import VeloxClip

/// Startup must not accuse the user of a conflict they did not create.
///
/// Every `register` call reported OS refusals through `ErrorHandler`, and round
/// 6 made those errors sticky and visible in the menu bar. The two changes
/// combined into a first-launch alert: the default shortcuts (F1/F2/F3 above
/// all) are routinely owned by macOS or another app, so a fresh install greeted
/// the user with a shortcut-conflict error before they had chosen anything.
@MainActor
final class ShortcutStartupNoiseTests: XCTestCase {

    override func setUp() async throws {
        ErrorHandler.shared.dismiss()
    }

    /// A shortcut string the parser accepts but the OS will refuse, because the
    /// slot next door already holds it.
    private let contested = "cmd+shift+v"

    func testStartupRegistrationDoesNotRaiseAnAlert() {
        let manager = ShortcutManager.shared
        // Claim the combination on one slot…
        manager.register(contested, for: .windowToggle, reportErrors: false) {}
        ErrorHandler.shared.dismiss()

        // …then have startup try to claim it on another. The OS refuses.
        manager.register(contested, for: .screenshot, reportErrors: false) {}

        XCTAssertNil(
            ErrorHandler.shared.currentError,
            "launching the app raised a shortcut alert the user did not cause"
        )
    }

    /// The Preferences path must keep reporting: there the user picked the
    /// combination and needs to know it did not take.
    func testPreferencesRegistrationStillReports() {
        let manager = ShortcutManager.shared
        manager.register(contested, for: .windowToggle, reportErrors: false) {}
        ErrorHandler.shared.dismiss()

        manager.register(contested, for: .pasteImage, reportErrors: true) {}

        XCTAssertNotNil(
            ErrorHandler.shared.currentError,
            "a shortcut the user chose in Preferences failed silently"
        )
        ErrorHandler.shared.dismiss()
    }

    /// Whichever way it fails, the slot that already worked must survive — the
    /// register-before-release rule from round 4.
    func testAFailedRegistrationKeepsTheWorkingHotkey() {
        let manager = ShortcutManager.shared
        manager.register("cmd+shift+u", for: .textCapture, reportErrors: false) {}
        let hadHotkey = manager.isRegistered(.textCapture)

        manager.register("not a shortcut", for: .textCapture, reportErrors: false) {}

        if hadHotkey {
            XCTAssertTrue(
                manager.isRegistered(.textCapture),
                "an unparseable replacement tore down the working hotkey"
            )
        }
        ErrorHandler.shared.dismiss()
    }
}
