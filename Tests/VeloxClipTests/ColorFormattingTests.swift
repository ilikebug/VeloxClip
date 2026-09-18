import XCTest
@testable import VeloxClip

final class ColorFormattingTests: XCTestCase {
    func testShortHexDoublesNibbles() {
        XCTAssertEqual(ColorFormatting.hex(from: "#f00"), "#FF0000")
    }

    func testEightDigitHexDropsAlphaFromHexButKeepsComponents() {
        XCTAssertEqual(ColorFormatting.hex(from: "#0A84FF80"), "#0A84FF")
        XCTAssertEqual(ColorFormatting.components(from: "#0A84FF80")?.a ?? 0, 128.0 / 255.0, accuracy: 0.001)
    }

    func testRgbFunctionFormatsHexAndRgb() {
        XCTAssertEqual(ColorFormatting.hex(from: "rgb(10, 132, 255)"), "#0A84FF")
        XCTAssertEqual(ColorFormatting.rgb(from: "#0A84FF"), "10 132 255")
    }

    func testOutOfRangeChannelsAreClampedToEightBits() {
        // Previously produced the 7-digit "#12C0000"
        XCTAssertEqual(ColorFormatting.hex(from: "rgb(300, 0, 0)"), "#FF0000")
        XCTAssertEqual(ColorFormatting.rgb(from: "rgb(300, 0, 999)"), "255 0 255")
        XCTAssertEqual(ColorFormatting.components(from: "rgba(0,0,0,7)")?.a, 1.0)
    }

    func testUnparseableReturnsNil() {
        XCTAssertNil(ColorFormatting.hex(from: "not a color"))
        XCTAssertNil(ColorFormatting.hex(from: "#12345"))
    }
}
