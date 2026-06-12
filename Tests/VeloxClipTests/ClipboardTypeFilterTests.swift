import XCTest
@testable import VeloxClip

final class ClipboardTypeFilterTests: XCTestCase {
    private func item(ofType type: String) -> ClipboardItem {
        ClipboardItem(type: type, content: "sample")
    }

    func testAllMatchesEveryType() {
        for type in ["text", "rtf", "color", "image", "file", "unknown"] {
            XCTAssertTrue(ClipboardTypeFilter.all.matches(item(ofType: type)), "all should match \(type)")
        }
    }

    func testTextAggregatesTextualTypes() {
        XCTAssertTrue(ClipboardTypeFilter.text.matches(item(ofType: "text")))
        XCTAssertTrue(ClipboardTypeFilter.text.matches(item(ofType: "rtf")))
        XCTAssertTrue(ClipboardTypeFilter.text.matches(item(ofType: "color")))
        XCTAssertFalse(ClipboardTypeFilter.text.matches(item(ofType: "image")))
        XCTAssertFalse(ClipboardTypeFilter.text.matches(item(ofType: "file")))
    }

    func testImageMatchesOnlyImages() {
        XCTAssertTrue(ClipboardTypeFilter.image.matches(item(ofType: "image")))
        XCTAssertFalse(ClipboardTypeFilter.image.matches(item(ofType: "text")))
        XCTAssertFalse(ClipboardTypeFilter.image.matches(item(ofType: "file")))
    }

    func testFileMatchesOnlyFiles() {
        XCTAssertTrue(ClipboardTypeFilter.file.matches(item(ofType: "file")))
        XCTAssertFalse(ClipboardTypeFilter.file.matches(item(ofType: "text")))
        XCTAssertFalse(ClipboardTypeFilter.file.matches(item(ofType: "image")))
    }
}
