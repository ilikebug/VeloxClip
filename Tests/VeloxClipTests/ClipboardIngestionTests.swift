import XCTest
import AppKit
@testable import VeloxClip

final class ClipboardIngestionTests: XCTestCase {
    // MARK: isColor

    func testIsColorAcceptsHexAndRgbForms() {
        XCTAssertTrue(ClipboardIngestion.isColor("#FFF"))
        XCTAssertTrue(ClipboardIngestion.isColor("#0a84ff"))
        XCTAssertTrue(ClipboardIngestion.isColor("#0A84FF80"))
        XCTAssertTrue(ClipboardIngestion.isColor(" rgb(10, 132, 255) "))
        XCTAssertTrue(ClipboardIngestion.isColor("rgba(10,132,255,0.5)"))
    }

    func testIsColorRejectsColorEmbeddedInSentence() {
        XCTAssertFalse(ClipboardIngestion.isColor("#FFF is my favourite"))
        XCTAssertFalse(ClipboardIngestion.isColor("#GGGGGG"))
        XCTAssertFalse(ClipboardIngestion.isColor("rgb(1,2)"))
    }

    // MARK: detectTags

    func testDetectTagsFindsEmailPhoneURLCodeAndJSON() {
        // NSDataDetector also reports mailto links, so an address carries both tags
        XCTAssertEqual(ClipboardIngestion.detectTags(in: "mail me: a.b@example.com"), ["URL", "Email"])
        XCTAssertEqual(ClipboardIngestion.detectTags(in: "call 555-123-4567"), ["Phone"])
        XCTAssertEqual(ClipboardIngestion.detectTags(in: "see https://example.com"), ["URL"])
        XCTAssertEqual(ClipboardIngestion.detectTags(in: "func main() -> Int"), ["Code"])
        XCTAssertEqual(ClipboardIngestion.detectTags(in: "{\"a\": 1}"), ["JSON"])
    }

    func testDetectTagsSkipsRegexScansOnHugeText() {
        // A pathological email-shaped payload beyond the cap must not be scanned
        let huge = String(repeating: "a", count: ClipboardIngestion.maxTaggableLength + 1) + "@b.co"
        XCTAssertEqual(ClipboardIngestion.detectTags(in: huge), [])
    }

    // MARK: recentDuplicate (5s window)

    func testRecentDuplicateMatchesSameTypeAndContentWithinWindow() {
        let item = ClipboardItem(type: "text", content: "hello")
        let found = ClipboardIngestion.recentDuplicate(
            in: [item], type: "text", content: "hello", dataHash: nil, now: item.createdAt.addingTimeInterval(4)
        )
        XCTAssertEqual(found?.id, item.id)
    }

    func testRecentDuplicateIgnoresItemsOlderThanWindow() {
        let item = ClipboardItem(type: "text", content: "hello")
        let found = ClipboardIngestion.recentDuplicate(
            in: [item], type: "text", content: "hello", dataHash: nil, now: item.createdAt.addingTimeInterval(6)
        )
        XCTAssertNil(found)
    }

    func testRecentDuplicateRequiresSameType() {
        let text = ClipboardItem(type: "text", content: "#FFFFFF")
        let found = ClipboardIngestion.recentDuplicate(
            in: [text], type: "color", content: "#FFFFFF", dataHash: nil, now: text.createdAt
        )
        XCTAssertNil(found)
    }

    // MARK: image limits

    func testUncompressedScreenshotSizedImageIsAccepted() {
        // Pasteboard TIFF is uncompressed: a 5K screen copy is ~59MB raw but a
        // few MB once normalized to PNG. The pixel guard, not the raw byte count,
        // is what separates a real screenshot from a decompression bomb.
        XCTAssertTrue(ClipboardIngestion.imageDimensionsWithinLimit(TestSupport.makePNG(width: 5120, height: 2880)))
        XCTAssertFalse(ClipboardIngestion.imageDimensionsWithinLimit(TestSupport.makePNG(width: 5120, height: 2880), maxPixels: 1000))
    }

    func testStorableImageRejectsAnOversizedNormalizedBlob() {
        // The byte cap applies to what actually goes into SQLite, not to the
        // uncompressed pasteboard bytes it was normalized from
        XCTAssertFalse(ClipboardIngestion.imageStorable(Data(count: 1024), maxBytes: 1023))
        XCTAssertTrue(ClipboardIngestion.imageStorable(Data(count: 1024), maxBytes: 1024))
    }

    func testImageDimensionsAreReadFromTheHeaderWithoutDecoding() {
        let png = TestSupport.makePNG(width: 20, height: 20)
        XCTAssertTrue(ClipboardIngestion.imageDimensionsWithinLimit(png, maxPixels: 400))
        XCTAssertFalse(ClipboardIngestion.imageDimensionsWithinLimit(png, maxPixels: 399))
    }

    func testUndecodableDataPassesTheDimensionGuard() {
        // Nothing will decode it, so it can't be a bomb — but it is still a copy to keep
        XCTAssertTrue(ClipboardIngestion.imageDimensionsWithinLimit(Data([0, 1, 2, 3]), maxPixels: 1))
    }

}
