import XCTest
@testable import VeloxClip

@MainActor
final class ShortcutManagerTests: XCTestCase {
    /// The documented regression at the heart of `update(_:for:)`: an
    /// unparseable string used to unregister the working hotkey first and then
    /// fail to register the new one, leaving the user with no shortcut at all.
    ///
    /// Asserted through `isRegistered` when the OS actually grants the hotkey,
    /// and skipped when it cannot — a headless CI runner has no window server,
    /// so RegisterEventHotKey fails for reasons that say nothing about us.
    func testUnparseableReplacementKeepsTheWorkingShortcut() throws {
        let manager = ShortcutManager()
        manager.register("cmd+shift+v", for: .windowToggle) {}
        try XCTSkipUnless(manager.isRegistered(.windowToggle),
                          "no window server — the OS refused the hotkey, nothing to assert about")

        manager.update("not a shortcut", for: .windowToggle)

        XCTAssertTrue(manager.isRegistered(.windowToggle),
                      "a bad replacement must leave the existing hotkey working")
    }

    /// The same rule, independent of whether the OS grants hotkeys: an
    /// unparseable string must be rejected before anything is torn down.
    func testUnparseableShortcutsAreRejectedBeforeAnyTeardown() {
        XCTAssertNil(ShortcutParser.parse("not a shortcut"))
        XCTAssertNil(ShortcutParser.parse(""))
        XCTAssertNil(ShortcutParser.parse("???"))
        XCTAssertNotNil(ShortcutParser.parse("cmd+shift+v"),
                        "…while a valid one still parses")
    }

    func testValidReplacementReRegisters() throws {
        let manager = ShortcutManager()
        manager.register("cmd+shift+v", for: .windowToggle) {}
        try XCTSkipUnless(manager.isRegistered(.windowToggle), "no window server")

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
