import XCTest
@testable import VeloxClip

final class TextCaptureContentTests: XCTestCase {
    func testBarcodePayloadTakesPrecedenceOverOCRText() {
        let result = TextCaptureService.chooseContent(
            ocrText: "Scan me ↑", barcodePayloads: ["https://example.com"])
        XCTAssertEqual(result, "https://example.com")
    }

    func testMultipleBarcodesJoinWithNewlines() {
        let result = TextCaptureService.chooseContent(
            ocrText: nil, barcodePayloads: ["a", "b"])
        XCTAssertEqual(result, "a\nb")
    }

    func testFallsBackToTrimmedOCRText() {
        let result = TextCaptureService.chooseContent(
            ocrText: "  hello world\n", barcodePayloads: [])
        XCTAssertEqual(result, "hello world")
    }

    func testEmptyEverythingReturnsNil() {
        XCTAssertNil(TextCaptureService.chooseContent(ocrText: nil, barcodePayloads: []))
        XCTAssertNil(TextCaptureService.chooseContent(ocrText: "   \n ", barcodePayloads: []))
    }
}
