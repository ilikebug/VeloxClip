import XCTest
import AppKit
import Carbon
@testable import VeloxClip

final class KeyCodeTableTests: XCTestCase {
    func testDigitKeysAreMapped() {
        // kVK_ANSI_1 = 18 … kVK_ANSI_0 = 29 (not sequential)
        XCTAssertEqual(KeyCodeTable.name(for: 18), "1")
        XCTAssertEqual(KeyCodeTable.name(for: 29), "0")
        XCTAssertEqual(KeyCodeTable.code(for: "1"), 18)
        XCTAssertEqual(KeyCodeTable.code(for: "0"), 29)
    }

    func testPunctuationMatchesCarbonConstants() {
        XCTAssertEqual(KeyCodeTable.name(for: UInt16(kVK_ANSI_Minus)), "-")
        XCTAssertEqual(KeyCodeTable.name(for: UInt16(kVK_ANSI_Equal)), "=")
        XCTAssertEqual(KeyCodeTable.name(for: UInt16(kVK_ANSI_LeftBracket)), "[")
        XCTAssertEqual(KeyCodeTable.name(for: UInt16(kVK_ANSI_RightBracket)), "]")
        XCTAssertEqual(KeyCodeTable.name(for: UInt16(kVK_ANSI_Backslash)), "\\")
        XCTAssertEqual(KeyCodeTable.code(for: "\\"), UInt16(kVK_ANSI_Backslash))
        XCTAssertEqual(KeyCodeTable.code(for: "["), UInt16(kVK_ANSI_LeftBracket))
    }

    func testEveryNameRoundTripsThroughItsCode() {
        for (code, name) in KeyCodeTable.namesByCode {
            XCTAssertEqual(KeyCodeTable.code(for: name), code, "\(name) should map back to \(code)")
        }
    }

    func testParseModifiersAndKey() {
        let parsed = ShortcutParser.parse("cmd+shift+1")
        XCTAssertEqual(parsed?.keyCode, 18)
        XCTAssertEqual(parsed?.modifiers, UInt32(cmdKey | shiftKey))
    }

    func testParseBareFunctionKeyHasNoModifiers() {
        let parsed = ShortcutParser.parse("f1")
        XCTAssertEqual(parsed?.keyCode, 122)
        XCTAssertEqual(parsed?.modifiers, 0)
    }

    func testParseRejectsModifierOnlyAndUnknownKeys() {
        XCTAssertNil(ShortcutParser.parse("cmd+shift"))
        XCTAssertNil(ShortcutParser.parse("cmd+🙂"))
        XCTAssertNil(ShortcutParser.parse(""))
    }

    func testStringFromRecordedEventRoundTrips() {
        XCTAssertEqual(ShortcutParser.string(modifiers: [.command, .shift], keyCode: 18), "cmd+shift+1")
        XCTAssertEqual(ShortcutParser.string(modifiers: [], keyCode: 122), "f1")
        // Unknown key must NOT degrade to a key-less "cmd+shift" string
        XCTAssertNil(ShortcutParser.string(modifiers: [.command, .shift], keyCode: 999))
    }
}
