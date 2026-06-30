import XCTest
import AppKit
@testable import VeloxClip

final class ContentDetectionServiceTests: XCTestCase {
    private func detect(_ content: String, type: String = "text") async -> DetectedContentType {
        let item = ClipboardItem(type: type, content: content, data: nil, sourceApp: nil)
        return await ContentDetectionService.shared.detectType(for: item)
    }

    // MARK: - Item-type shortcuts

    func testItemTypeOverridesContent() async {
        let image = ClipboardItem(type: "image", content: nil, data: Data([0x89]), sourceApp: nil)
        let color = ClipboardItem(type: "color", content: "#FF0000", data: nil, sourceApp: nil)
        let file = ClipboardItem(type: "file", content: "/tmp/a.txt", data: nil, sourceApp: nil)

        let imageType = await ContentDetectionService.shared.detectType(for: image)
        let colorType = await ContentDetectionService.shared.detectType(for: color)
        let fileType = await ContentDetectionService.shared.detectType(for: file)

        XCTAssertEqual(imageType, .image)
        XCTAssertEqual(colorType, .color)
        XCTAssertEqual(fileType, .file)
    }

    // MARK: - URL

    func testDetectsURLs() async {
        let https = await detect("https://example.com/path?q=1")
        let http = await detect("http://example.com")
        XCTAssertEqual(https, .url)
        XCTAssertEqual(http, .url)
    }

    func testMultilineContentIsNotURL() async {
        let result = await detect("https://example.com\nsecond line")
        XCTAssertNotEqual(result, .url)
    }

    // MARK: - JSON

    func testDetectsJSONObjectAndArray() async {
        let object = await detect(#"{"name": "VeloxClip", "version": 1}"#)
        let array = await detect(#"[1, 2, 3]"#)
        XCTAssertEqual(object, .json)
        XCTAssertEqual(array, .json)
    }

    func testInvalidJSONIsNotJSON() async {
        let result = await detect(#"{"name": broken}"#)
        XCTAssertNotEqual(result, .json)
    }

    // MARK: - Table

    func testDetectsTabSeparatedTable() async {
        let result = await detect("name\tage\nalice\t30\nbob\t25")
        XCTAssertEqual(result, .table)
    }

    func testDetectsPipeSeparatedTable() async {
        let result = await detect("name | age | city\nalice | 30 | Paris")
        XCTAssertEqual(result, .table)
    }

    func testProseWithSinglePipePerLineIsNotTable() async {
        let result = await detect("状态 | 需要确认\n结果 | 暂时未知")
        XCTAssertNotEqual(result, .table)
    }

    func testProseWithOneCommaPerLineIsNotTable() async {
        let result = await detect("Hello, world\nGoodbye, world")
        XCTAssertNotEqual(result, .table)
    }

    // MARK: - DateTime

    func testDetectsDateTimeFormats() async {
        for sample in ["2026-06-12", "2026-06-12T14:30:00Z", "12/06/2026", "14:30", "1718200000", "1718200000000"] {
            let result = await detect(sample)
            XCTAssertEqual(result, .datetime, "\(sample) should be datetime")
        }
    }

    func testBranchNamesAndPathsAreNotDateTime() async {
        for sample in ["my-branch-name", "a/b/c", "v1.2.3"] {
            let result = await detect(sample)
            XCTAssertNotEqual(result, .datetime, "\(sample) must not be datetime")
        }
    }

    // MARK: - Code / Markdown / Long text

    func testDetectsCodeWithMultipleIndicators() async {
        let result = await detect("func hello() {\n    let x = 1\n}")
        XCTAssertEqual(result, .code)
    }

    func testSingleKeywordProseIsNotCode() async {
        let result = await detect("please import the spreadsheet")
        XCTAssertNotEqual(result, .code)
    }

    func testDetectsMarkdownByHeader() async {
        let result = await detect("# Title\n\nSome body text.")
        XCTAssertEqual(result, .markdown)
    }

    func testDetectsLongText() async {
        let result = await detect(String(repeating: "lorem ipsum ", count: 60))
        XCTAssertEqual(result, .longtext)
    }

    func testShortPlainText() async {
        let result = await detect("hello world")
        XCTAssertEqual(result, .plain)
    }

    func testEmptyContentIsPlain() async {
        let item = ClipboardItem(type: "text", content: nil, data: nil, sourceApp: nil)
        let result = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertEqual(result, .plain)
    }

    // MARK: - Cache

    func testDetectionIsCachedPerItemID() async {
        let item = ClipboardItem(type: "text", content: #"{"a": 1}"#, data: nil, sourceApp: nil)
        let first = await ContentDetectionService.shared.detectType(for: item)

        // Same id with different content returns the cached result
        var mutated = item
        mutated.content = "plain now"
        let second = await ContentDetectionService.shared.detectType(for: mutated)

        XCTAssertEqual(first, .json)
        XCTAssertEqual(second, .json)
    }
}

final class SensitivePasteboardMarkerTests: XCTestCase {
    func testConcealedTypeIsDetected() {
        let types = [
            NSPasteboard.PasteboardType.string,
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        ]
        XCTAssertTrue(ClipboardMonitor.containsSensitiveMarker(types))
    }

    func testTransientAndAutoGeneratedAreDetected() {
        XCTAssertTrue(ClipboardMonitor.containsSensitiveMarker(
            [NSPasteboard.PasteboardType("org.nspasteboard.TransientType")]
        ))
        XCTAssertTrue(ClipboardMonitor.containsSensitiveMarker(
            [NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")]
        ))
    }

    func testOrdinaryTypesAreNotSensitive() {
        let types: [NSPasteboard.PasteboardType] = [.string, .tiff, .png, .rtf, .fileURL]
        XCTAssertFalse(ClipboardMonitor.containsSensitiveMarker(types))
    }

    func testNilAndEmptyTypeListsAreNotSensitive() {
        XCTAssertFalse(ClipboardMonitor.containsSensitiveMarker(nil))
        XCTAssertFalse(ClipboardMonitor.containsSensitiveMarker([]))
    }
}
