import XCTest
@testable import VeloxClip

final class RowPresentationTests: XCTestCase {

    // MARK: - iconKind

    func testIconKindByType() {
        XCTAssertEqual(RowPresentation.iconKind(type: "color", tags: []), .color)
        XCTAssertEqual(RowPresentation.iconKind(type: "image", tags: []), .image)
        XCTAssertEqual(RowPresentation.iconKind(type: "file", tags: []), .file)
        XCTAssertEqual(RowPresentation.iconKind(type: "rtf", tags: []), .rtf)
        XCTAssertEqual(RowPresentation.iconKind(type: "text", tags: []), .text)
    }

    func testIconKindByTag() {
        // Real tag strings are capitalized (ClipboardMonitor.detectTags): URL/Code/JSON
        XCTAssertEqual(RowPresentation.iconKind(type: "text", tags: ["URL"]), .url)
        XCTAssertEqual(RowPresentation.iconKind(type: "text", tags: ["JSON"]), .json)
        XCTAssertEqual(RowPresentation.iconKind(type: "text", tags: ["Code"]), .code)
        // Case-insensitive so lowercase tags work too
        XCTAssertEqual(RowPresentation.iconKind(type: "text", tags: ["url"]), .url)
        XCTAssertEqual(RowPresentation.iconKind(type: "text", tags: ["json"]), .json)
        XCTAssertEqual(RowPresentation.iconKind(type: "text", tags: ["code"]), .code)
    }

    func testIconKindTypeWinsOverTags() {
        // A color/image/file item keeps its swatch/thumbnail/folder even if tagged
        XCTAssertEqual(RowPresentation.iconKind(type: "color", tags: ["URL"]), .color)
        XCTAssertEqual(RowPresentation.iconKind(type: "image", tags: ["JSON"]), .image)
        XCTAssertEqual(RowPresentation.iconKind(type: "file", tags: ["Code"]), .file)
    }

    // MARK: - subtitle

    func testSubtitleText() {
        XCTAssertEqual(RowPresentation.subtitle(type: "text", content: "hello", tags: []), "纯文本 · 5 字")
        XCTAssertEqual(RowPresentation.subtitle(type: "text", content: "hello", tags: [], language: .en), "Plain Text · 5 chars")
    }

    func testSubtitleJSONObject() {
        XCTAssertEqual(
            RowPresentation.subtitle(type: "text", content: "{\"a\":1,\"b\":2}", tags: ["JSON"]),
            "JSON · 2 个键"
        )
        XCTAssertEqual(
            RowPresentation.subtitle(type: "text", content: "{\"a\":1,\"b\":2}", tags: ["JSON"], language: .en),
            "JSON · 2 keys"
        )
    }

    func testSubtitleJSONArray() {
        XCTAssertEqual(
            RowPresentation.subtitle(type: "text", content: "[1,2,3]", tags: ["JSON"]),
            "JSON · 3 项"
        )
    }

    func testSubtitleColor() {
        XCTAssertEqual(RowPresentation.subtitle(type: "color", content: "#0A84FF", tags: []), "RGB 10 · 132 · 255 · 颜色")
    }

    func testSubtitleURL() {
        XCTAssertEqual(
            RowPresentation.subtitle(type: "text", content: "https://www.apple.com/mac", tags: ["URL"]),
            "www.apple.com · 链接"
        )
    }

    func testSubtitleCode() {
        let code = "func a() {}\nlet x = 1\nprint(x)"
        XCTAssertTrue(RowPresentation.subtitle(type: "text", content: code, tags: ["Code"]).contains("3 行"))
    }

    func testSubtitleRTF() {
        XCTAssertEqual(RowPresentation.subtitle(type: "rtf", content: "hello", tags: []), "富文本 · 5 字")
    }

    func testSubtitleFileSingle() {
        XCTAssertEqual(
            RowPresentation.subtitle(type: "file", content: "/Users/me/Documents/a.txt", tags: []),
            "Documents · 文件"
        )
    }

    func testSubtitleFileMultiple() {
        XCTAssertEqual(
            RowPresentation.subtitle(type: "file", content: "/Users/me/Documents/a.txt\n/Users/me/Documents/b.txt", tags: []),
            "2 个文件 · Documents · 文件"
        )
        XCTAssertEqual(
            RowPresentation.subtitle(type: "file", content: "/Users/me/Documents/a.txt\n/Users/me/Documents/b.txt", tags: [], language: .en),
            "2 files · Documents · File"
        )
    }

    func testSubtitleImage() {
        XCTAssertEqual(RowPresentation.subtitle(type: "image", content: nil, tags: []), "图片")
    }

    func testSubtitleNilContentFallback() {
        XCTAssertEqual(RowPresentation.subtitle(type: "text", content: nil, tags: []), "未知内容")
    }

    // MARK: - relativeTime

    func testRelativeTimeJustNow() {
        let now = Date()
        XCTAssertEqual(RowPresentation.relativeTime(now.addingTimeInterval(-30), now: now), "刚刚")
    }

    func testRelativeTimeMinutes() {
        let now = Date()
        XCTAssertEqual(RowPresentation.relativeTime(now.addingTimeInterval(-120), now: now), "2 分钟")
        XCTAssertEqual(RowPresentation.relativeTime(now.addingTimeInterval(-120), now: now, language: .en), "2 min")
    }

    func testRelativeTimeHours() {
        let now = Date()
        XCTAssertEqual(RowPresentation.relativeTime(now.addingTimeInterval(-3 * 3600), now: now), "3 小时")
    }

    func testRelativeTimeYesterday() {
        // Anchor `now` at midday so "calendar yesterday" is unambiguous regardless
        // of when the test runs.
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let yesterdayMorning = cal.date(byAdding: .day, value: -1, to: now)!
            .addingTimeInterval(-2 * 3600) // 10:00 the previous calendar day
        XCTAssertEqual(RowPresentation.relativeTime(yesterdayMorning, now: now), "昨天")
    }

    func testRelativeTime25HoursAgoTwoCalendarDaysBackIsNotYesterday() {
        // now = 00:30; 25h earlier = 23:30 *two* calendar days ago. Old fixed-seconds
        // logic (<172800s) called this "昨天"; the calendar check correctly does NOT,
        // falling through to the M月D日 branch.
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 0, minute: 30, second: 0, of: Date())!
        let result = RowPresentation.relativeTime(now.addingTimeInterval(-25 * 3600), now: now)
        XCTAssertNotEqual(result, "昨天")
        XCTAssertTrue(result.contains("月") && result.contains("日"))
    }
}
