import XCTest
import AppKit
import SwiftUI
@testable import VeloxClip

/// Round-8 audit findings in the code round 7 did not cover: preview
/// components, the editor eraser, ingestion and the shortcut settings.
@MainActor
final class Round8RegressionTests: XCTestCase {

    // MARK: - JSON text views rewrote the data

    /// JSONSerialization re-serialization turned 19.99 into 19.989999999999998
    /// and "/" into "\/", and Copy put that on the clipboard.
    func testPrettyKeepsNumberLiteralsSlashesAndEscapesVerbatim() {
        let source = #"{"p":19.99,"q":0.1,"big":12345678901234567890,"u":"https://a/b","e":"café \"x\""}"#
        let pretty = JSONTextFormatting.pretty(source)
        XCTAssertTrue(pretty.contains("19.99,"), pretty)
        XCTAssertTrue(pretty.contains("0.1,"), pretty)
        XCTAssertTrue(pretty.contains("12345678901234567890"), pretty)
        XCTAssertTrue(pretty.contains(#""https://a/b""#), pretty)
        XCTAssertTrue(pretty.contains(#""café \"x\"""#), pretty)
    }

    func testPrettyLayout() {
        let source = #"{"a":[1,{"b":"x, y: {z}"}],"c":{},"d":[]}"#
        let expected = """
        {
          "a" : [
            1,
            {
              "b" : "x, y: {z}"
            }
          ],
          "c" : {},
          "d" : []
        }
        """
        XCTAssertEqual(JSONTextFormatting.pretty(source), expected)
    }

    func testMinifiedDropsOnlyWhitespaceOutsideStrings() {
        let source = "{\n  \"k\" : \"a  b\",\n  \"n\" : 1.50\n}"
        XCTAssertEqual(JSONTextFormatting.minified(source), #"{"k":"a  b","n":1.50}"#)
    }

    func testFormattingKeepsNonASCIIText() {
        let source = #"{"名字":"张三 😀"}"#
        XCTAssertEqual(JSONTextFormatting.minified(source), source)
        XCTAssertTrue(JSONTextFormatting.pretty(source).contains(#""名字" : "张三 😀""#))
    }

    // MARK: - Text annotations could not be erased

    /// A text element's path is a single move-to; stroking it yields an empty
    /// path, so the eraser never hit it.
    func testEraserRemovesTextAnywhereOnItsBox() {
        let state = EditorState()
        let anchor = CGPoint(x: 100, y: 100)
        let path = CGMutablePath()
        path.move(to: anchor)
        state.addElement(DrawingElement(type: .text, path: path, color: .red, lineWidth: 1,
                                        startPoint: anchor, endPoint: anchor,
                                        text: "Hello annotation", fontSize: 24))

        state.eraseElements(at: CGPoint(x: 400, y: 400), radius: 5)
        XCTAssertEqual(state.elements.count, 1, "a far-away swipe must not erase it")

        // Inside the text, well right of the anchor point
        state.eraseElements(at: CGPoint(x: 140, y: 102), radius: 5)
        XCTAssertTrue(state.elements.isEmpty)
    }

    // MARK: - A, B, A within 5s left B on top

    func testRepeatWindowOnlyMatchesTheNewestItem() {
        let a = ClipboardItem(type: "text", content: "A")
        let b = ClipboardItem(type: "text", content: "B")
        let now = a.createdAt.addingTimeInterval(2)

        XCTAssertNil(ClipboardIngestion.recentDuplicate(in: [b, a], type: "text", content: "A", dataHash: nil, now: now),
                     "a repeat of the second row must reach addItem, which moves it to the top")
        XCTAssertEqual(ClipboardIngestion.recentDuplicate(in: [a, b], type: "text", content: "A", dataHash: nil, now: now)?.id,
                       a.id, "the same copy repeated on top is still absorbed")
    }

    // MARK: - Date preview: trailing newline and two-digit years

    private func ymd(_ date: Date?) -> String? {
        guard let date else { return nil }
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    func testDateWithTrailingNewlineParses() {
        XCTAssertEqual(ymd(DateTimePreviewPresentation.date(from: "2026-06-12\n")), "2026-6-12")
        XCTAssertNotNil(DateTimePreviewPresentation.date(from: "1730000000\n"))
        XCTAssertEqual(DateTimePreviewPresentation.unixTimestampString(for: "1730000000\n"), "1730000000")
    }

    func testTwoDigitYearIsNotTheFirstCentury() {
        XCTAssertEqual(ymd(DateTimePreviewPresentation.date(from: "12/06/26")), "2026-12-6")
    }

    func testFourDigitYearsAndEpochsStillParse() {
        XCTAssertEqual(ymd(DateTimePreviewPresentation.date(from: "12/06/2026")), "2026-12-6")
        XCTAssertEqual(ymd(DateTimePreviewPresentation.date(from: "2026-06-12")), "2026-6-12")
        let epoch = DateTimePreviewPresentation.date(from: "1730000000")
        XCTAssertEqual(epoch?.timeIntervalSince1970, 1_730_000_000)
    }

    // MARK: - Shortcut recorder accepted Shift / Option alone

    func testShiftOrOptionAloneIsNotRecordable() {
        let keyA: UInt16 = 0
        XCTAssertFalse(ShortcutParser.isRecordable(modifiers: [.shift], keyCode: keyA))
        XCTAssertFalse(ShortcutParser.isRecordable(modifiers: [.option], keyCode: keyA))
        XCTAssertFalse(ShortcutParser.isRecordable(modifiers: [.shift, .option], keyCode: keyA))
        XCTAssertFalse(ShortcutParser.isRecordable(modifiers: [], keyCode: keyA))
    }

    func testCommandControlAndFunctionKeysAreRecordable() {
        let keyA: UInt16 = 0
        XCTAssertTrue(ShortcutParser.isRecordable(modifiers: [.command, .shift], keyCode: keyA))
        XCTAssertTrue(ShortcutParser.isRecordable(modifiers: [.control, .option], keyCode: keyA))
        XCTAssertTrue(ShortcutParser.isRecordable(modifiers: [], keyCode: 122)) // F1
    }

    // MARK: - A refused shortcut was persisted anyway

    func testRefusedShortcutIsRevertedAndNotPersisted() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        let before = settings.textCaptureShortcut

        settings.textCaptureShortcut = "not a shortcut"

        XCTAssertEqual(settings.textCaptureShortcut, before, "the setting must match the hotkey still live")
        try await Task.sleep(nanoseconds: 100_000_000)
        let stored = await db.getSetting(key: "textCaptureShortcut")
        XCTAssertNotEqual(stored, "not a shortcut")
    }
}
