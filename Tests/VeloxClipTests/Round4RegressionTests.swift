import XCTest
@testable import VeloxClip

/// Round-5 findings against the round-4 fixes. Six of these are regressions the
/// round-4 commit introduced; each fails at f932572 and passes at its parent.
final class Round4RegressionTests: XCTestCase {

    private func chunk(_ text: String) -> [String] {
        MarkdownView.chunk(text).map(\.content)
    }

    // MARK: - Fence detection

    /// Round 4 added `~~~` fence support without an info-string check, so a run
    /// of tildes used as a visual divider — common in READMEs and chat logs —
    /// opens a code block that never closes and swallows the document.
    func testTildeDividerDoesNotSwallowTheDocument() {
        let doc = """
        # Title

        Some intro prose.

        ~~~~~~~~~~~~~~~~

        # Second heading

        More prose after the divider.
        """
        let chunks = chunk(doc)
        XCTAssertTrue(
            chunks.contains { $0.contains("# Second heading") && !$0.contains("~~~~") },
            "the heading after a tilde divider must still be a heading; got \(chunks)"
        )
    }

    /// The control: a dash divider was never affected.
    func testDashDividerControlStillWorks() {
        let doc = "# Title\n\nProse.\n\n----------------\n\n# Second heading\n\nMore."
        XCTAssertTrue(chunk(doc).contains { $0.contains("# Second heading") })
    }

    /// A real tilde fence must still protect its content.
    func testRealTildeFenceStillProtectsItsContent() {
        let doc = "Intro.\n\n~~~c\n# include <stdio.h>\nint main() {}\n~~~\n\nAfter."
        let chunks = chunk(doc)
        XCTAssertTrue(
            chunks.contains { $0.contains("~~~c") && $0.contains("# include") },
            "a fence with an info string must keep its content together; got \(chunks)"
        )
    }

    /// A bare ``` divider run with no closer must not swallow the rest either.
    func testBacktickDividerRunDoesNotSwallowTheDocument() {
        let doc = "# Title\n\nProse.\n\n````````````````\n\n# Second heading\n\nMore."
        let chunks = chunk(doc)
        XCTAssertTrue(
            chunks.contains { $0.contains("# Second heading") && !$0.contains("````") },
            "got \(chunks)"
        )
    }

    // MARK: - List heuristics

    /// Round 4 fixed `1984. It was…` for the `. ` form and simultaneously added
    /// the `N) ` form, re-opening the same gluing bug for parens.
    func testParenNumberProseDoesNotGlueTheNextList() {
        let doc = """
        The statute is section 12 subsection 3) which applies here.
        1) is also how the German ordinal is written in this sentence.

        1) real first
        2) real second
        """
        let chunks = chunk(doc)
        XCTAssertFalse(
            chunks.count == 1,
            "prose must not be welded to the list that follows it; got \(chunks)"
        )
    }

    /// A genuine short-numbered paren list must still hold together.
    func testGenuineParenListStaysOneDocument() {
        let doc = "1) first\n2) second\n3) third"
        XCTAssertEqual(chunk(doc).count, 1, "a real paren list must stay one chunk")
    }

    /// The round-4 `isIndentedContinuation` rule is dead on the backward side:
    /// `lastNonEmptyLine` is assigned the TRIMMED line, so the predicate can
    /// never fire. A numbered how-to with an indented explanation therefore
    /// splits and MarkdownUI restarts the numbering at 1.
    func testOrderedListWithIndentedContinuationStaysOneDocument() {
        let doc = """
        1. install the tool
           run the installer and accept the licence

        2. configure it

        3. restart
        """
        let chunks = chunk(doc)
        XCTAssertEqual(
            chunks.count, 1,
            "a loose ordered list with a continuation line must stay one document, or the numbering restarts; got \(chunks)"
        )
    }

    func testBulletListWithIndentedContinuationStaysOneDocument() {
        let doc = "- outer item\n\n  a continuation paragraph\n\n  another continuation paragraph"
        XCTAssertEqual(chunk(doc).count, 1, "got \(chunk(doc))")
    }

    // MARK: - Epoch range

    /// The round-4 ceiling of 2e9 excludes 2147483647 — INT32_MAX, the Y2038
    /// epoch and the most-copied timestamp constant in software.
    func testY2038AndLaterEpochsAreStillDates() async {
        for value in ["2147483647", "2050000000"] {
            let item = ClipboardItem(type: "text", content: value)
            let type = await ContentDetectionService.shared.detectType(for: item)
            XCTAssertEqual(type, .datetime, "\(value) must still be detected as a date, got \(type)")
        }
    }

    /// …without re-admitting the ISBNs and order numbers round 4 fixed.
    func testLongNumbersAreStillNotDates() async {
        for value in ["9780134685991", "9876543210", "12345678901234567890"] {
            let item = ClipboardItem(type: "text", content: value)
            let type = await ContentDetectionService.shared.detectType(for: item)
            XCTAssertNotEqual(type, .datetime, "\(value) must not be a date, got \(type)")
        }
    }

    // MARK: - Table heuristic

    /// Round 4 ANDed the two-column guard with `lines.count < 3`, so any three
    /// lines with one comma each became a table. That is ordinary prose.
    func testProseWithOneCommaPerLineIsNotATable() async {
        let prose = "Alice, the project lead\nBob, the designer\nCarol, the engineer"
        let item = ClipboardItem(type: "text", content: prose)
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertNotEqual(type, .table, "a three-line name list is not a table, got \(type)")
    }

    func testSentencesWithOneCommaEachAreNotATable() async {
        let prose = "When it rains, I stay indoors.\nWhen it snows, I ski.\nWhen it is sunny, I walk."
        let item = ClipboardItem(type: "text", content: prose)
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertNotEqual(type, .table, "three sentences are not a table, got \(type)")
    }

    /// A real two-column CSV export must still be a table — the round-4 fix
    /// this is narrowing was itself fixing a real bug.
    func testRealTwoColumnCSVIsStillATable() async {
        let csv = "name,age\nAlice,30\nBob,25\nCarol,41\nDave,19"
        let item = ClipboardItem(type: "text", content: csv)
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertEqual(type, .table, "a 2-column CSV export must render as a table, got \(type)")
    }

    // MARK: - Shortcut registration

    /// Round 4 rewrote update() to register-before-release, then changed
    /// register() in the opposite direction in the same commit: it now tears
    /// down a working hotkey before validating the replacement.
    @MainActor
    func testRegisterWithAnUnparseableShortcutKeepsTheWorkingOne() {
        let manager = ShortcutManager.shared
        manager.register("cmd+shift+v", for: .windowToggle) {}
        let hadHotkey = manager.isRegistered(.windowToggle)

        manager.register("not a shortcut", for: .windowToggle) {}

        if hadHotkey {
            XCTAssertTrue(
                manager.isRegistered(.windowToggle),
                "register() with an unparseable string tore down the working hotkey"
            )
        }
    }
}
