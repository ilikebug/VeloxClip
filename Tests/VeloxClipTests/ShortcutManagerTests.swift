import XCTest
@testable import VeloxClip

@MainActor
final class ShortcutManagerTests: XCTestCase {
    /// The documented regression at the heart of `update(_:for:)`: an
    /// unparseable string used to unregister the working hotkey first and then
    /// fail to register the new one, leaving the user with no shortcut at all.
    ///
    /// Previously untestable — the manager read AppSettings.shared directly and
    /// dispatched into four other singletons, so it could not be constructed in
    /// a test at all.
    func testUnparseableReplacementKeepsTheWorkingShortcut() {
        let manager = ShortcutManager()
        manager.register("cmd+shift+v", for: .windowToggle) {}
        XCTAssertTrue(manager.isRegistered(.windowToggle), "precondition: the original registered")

        manager.update("not a shortcut", for: .windowToggle)

        XCTAssertTrue(manager.isRegistered(.windowToggle),
                      "a bad replacement must leave the existing hotkey working")
    }

    func testValidReplacementReRegisters() {
        let manager = ShortcutManager()
        manager.register("cmd+shift+v", for: .windowToggle) {}

        manager.update("cmd+shift+b", for: .windowToggle)

        XCTAssertTrue(manager.isRegistered(.windowToggle))
    }

    func testAnUnparseableInitialShortcutRegistersNothing() {
        let manager = ShortcutManager()
        manager.register("???", for: .screenshot) {}
        XCTAssertFalse(manager.isRegistered(.screenshot))
    }

    /// Slot ids are the wire format for the Carbon callback's dispatch table;
    /// changing one silently rebinds a user's shortcut to another action.
    func testSlotRawValuesAreStable() {
        XCTAssertEqual(ShortcutManager.Slot.windowToggle.rawValue, 1)
        XCTAssertEqual(ShortcutManager.Slot.screenshot.rawValue, 2)
        XCTAssertEqual(ShortcutManager.Slot.pasteImage.rawValue, 3)
        XCTAssertEqual(ShortcutManager.Slot.textCapture.rawValue, 4)
        XCTAssertEqual(Set(ShortcutManager.Slot.allCases.map(\.rawValue)).count,
                       ShortcutManager.Slot.allCases.count,
                       "slot ids must be unique")
    }
}
