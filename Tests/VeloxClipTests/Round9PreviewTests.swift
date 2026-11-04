import XCTest
import AppKit
import SwiftUI
@testable import VeloxClip

/// Round-9 low-priority audit findings in the preview components, the
/// command palette and content detection.
@MainActor
final class Round9PreviewTests: XCTestCase {

    // MARK: - A future date read "-N seconds ago"

    func testFutureDateReadsAsFromNow() {
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: -30, language: .en), "in 30 seconds")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: -7_200, language: .en), "in 2 hours")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: -172_800, language: .zhHans), "2 天后")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 120, language: .en), "2 minutes ago")
    }

    // MARK: - Detected as a date, then not parsed

    private func detect(_ content: String) async -> DetectedContentType {
        await ContentDetectionService.shared.detectType(for: ClipboardItem(type: "text", content: content))
    }

    func testEveryDetectedDateShapeParses() async {
        let samples = ["2026-06-12 10:00", "2026-06-12T10:00", "2026-06-12T10:00:00",
                       "2026-06-12T10:00:00.123", "2026-06-12T10:00Z", "2026-06-12 10:00+08:00",
                       "2026/06/12 10:00", "14:30", "14:30:05", "9:05"]
        for sample in samples {
            let type = await detect(sample)
            XCTAssertEqual(type, .datetime, sample)
            XCTAssertNotNil(DateTimePreviewPresentation.date(from: sample), sample)
        }
    }

    func testDateWithoutZoneIsLocalTime() throws {
        let date = try XCTUnwrap(DateTimePreviewPresentation.date(from: "2026-06-12T10:00:00"))
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 6, 12, 10, 0])
    }

    func testExplicitOffsetIsHonoured() throws {
        let date = try XCTUnwrap(DateTimePreviewPresentation.date(from: "2026-06-12 10:00+08:00"))
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_781_229_600))  // 2026-06-12T02:00:00Z
    }

    func testBareTimeIsTodayAtThatTime() throws {
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 8)))
        let date = try XCTUnwrap(DateTimePreviewPresentation.date(from: "14:30", now: now))
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 3, 4, 14, 30])
    }

    func testImpossibleDatesStillDoNotParse() {
        XCTAssertNil(DateTimePreviewPresentation.date(from: "2026-02-30 10:00"))
        XCTAssertNil(DateTimePreviewPresentation.date(from: "25:61"))
    }

    // MARK: - HSL truncated instead of rounded

    func testHSLRowIsRounded() throws {
        let comp = try XCTUnwrap(ColorFormatting.components(from: "#0A84FF"))
        XCTAssertEqual(ColorPreviewFormats.rows(for: comp).first { $0.name == "HSL" }?.value, "210 100 52")
    }

    func testHueRoundingUpTo360WrapsToZero() throws {
        let comp = try XCTUnwrap(ColorFormatting.components(from: "#FF0001"))
        XCTAssertEqual(ColorPreviewFormats.rows(for: comp).first { $0.name == "HSL" }?.value, "0 100 50")
    }

    // MARK: - Summary and keywords for Chinese text

    func testChineseSummaryIsFirstThreeSentences() {
        let text = "第一句话。第二句话！第三句话？第四句话。"
        XCTAssertEqual(TextSummaryPresentation.summary(for: text), "第一句话。第二句话！第三句话？")
    }

    func testEnglishSummaryIsFirstThreeSentences() {
        let text = "One here. Two there! Three now? Four never."
        XCTAssertEqual(TextSummaryPresentation.summary(for: text), "One here. Two there! Three now?")
    }

    func testChineseKeywordsAreWordsNotSentences() {
        let text = "苹果公司发布了新产品。苹果公司的新产品很受欢迎。"
        let keywords = TextSummaryPresentation.keywords(in: text)
        XCTAssertTrue(keywords.contains("苹果"), "\(keywords)")
        XCTAssertFalse(keywords.contains { $0.count > 6 }, "\(keywords)")
    }

    // MARK: - File icon for media UTIs

    func testFileIconRecognisesMediaTypeIdentifiers() {
        XCTAssertEqual(SingleFilePreview.fileIcon(for: "public.jpeg"), "photo")
        XCTAssertEqual(SingleFilePreview.fileIcon(for: "public.png"), "photo")
        XCTAssertEqual(SingleFilePreview.fileIcon(for: "com.apple.quicktime-movie"), "video")
        XCTAssertEqual(SingleFilePreview.fileIcon(for: "public.mpeg-4"), "video")
        XCTAssertEqual(SingleFilePreview.fileIcon(for: "public.mp3"), "music.note")
        XCTAssertEqual(SingleFilePreview.fileIcon(for: "public.plain-text"), "doc.text")
        XCTAssertEqual(SingleFilePreview.fileIcon(for: "public.folder"), "folder")
    }

    // MARK: - Markdown tables in the table preview

    func testMarkdownTableHasNoBorderColumnsOrRuleRow() {
        let source = """
        | name | age |
        |---|:---:|
        | Alice | 30 |
        | Bob | 41 |
        """
        let table = TablePreviewView.parsedTable(source, delimiter: "|", query: "")
        XCTAssertEqual(table.headers, ["name", "age"])
        XCTAssertEqual(table.rows, [["Alice", "30"], ["Bob", "41"]])
    }

    func testUnfencedPipeTableAndTSVKeepEmptyCells() {
        XCTAssertEqual(TablePreviewView.parsedTable("a | b | c\n1 | | 3", delimiter: "|", query: "").rows, [["1", "", "3"]])
        XCTAssertEqual(TablePreviewView.parsedTable("a\tb\tc\n\t2\t3", delimiter: "\t", query: "").rows, [["", "2", "3"]])
    }

    /// Only the line under the header is the rule; a "-" placeholder row is data.
    func testDashPlaceholderRowIsKept() {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |\n| - | - |"
        XCTAssertEqual(TablePreviewView.parsedTable(source, delimiter: "|", query: "").rows, [["1", "2"], ["-", "-"]])
    }

    /// Unfenced pipe data: a leading "|" is an empty first field, not a border.
    func testUnfencedLeadingPipeIsAnEmptyField() {
        XCTAssertEqual(TablePreviewView.parsedTable("a|b|c\n|y|z", delimiter: "|", query: "").rows, [["", "y", "z"]])
    }

    /// Full-width digits match `\d`, which made the zone offset force-unwrap trap.
    func testFullWidthDigitsDoNotCrashTheParser() {
        XCTAssertNil(DateTimePreviewPresentation.date(from: "2026-06-12T10:00+０５:３０"))
        XCTAssertNil(DateTimePreviewPresentation.date(from: "２０２６-０６-１２ １０:００"))
        XCTAssertNil(DateTimePreviewPresentation.date(from: "2026-06-12 １０:００"))
    }

    // MARK: - Re-parsing dropped the active search

    func testReparseKeepsTheActiveSearch() {
        let table = TablePreviewView.parsedTable("name,age\nAlice,30\nBob,41", delimiter: ",", query: "BOB")
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.filteredRows, [["Bob", "41"]])
    }

    // MARK: - Palette filter was not trimmed

    func testPaletteFilterIgnoresSurroundingWhitespace() {
        let commands = CommandResolver.commands(forType: "text", language: .en)
        XCTAssertEqual(CommandPaletteView.filter(commands, by: " delete ").map(\.kind), [.delete])
        XCTAssertEqual(CommandPaletteView.filter(commands, by: "  ").count, commands.count)
    }
}
