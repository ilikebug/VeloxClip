import XCTest
import SwiftUI
import AppKit
@testable import VeloxClip

/// The preview must show the colour that was actually copied.
///
/// `extractRGB` round-tripped the parsed colour through
/// `Color -> NSColor.getRed -> Int(r * 255)`. NSColor returns extended-sRGB
/// components, so an exact 11 comes back as 10.999997 and `Int()` floors it:
/// 75 of 256 channel values displayed one lower than the source. Worse, the
/// HEX row was built from those truncated numbers while the "Copy HEX" button
/// formatted the raw source string, so the two disagreed.
final class ColorPreviewAccuracyTests: XCTestCase {
    /// Every 8-bit channel value must survive the pipeline intact.
    func testEveryChannelValueSurvivesTheRoundTrip() {
        var wrong: [Int] = []
        for value in 0...255 {
            let hex = String(format: "#%02X%02X%02X", value, value, value)
            guard let comp = ColorFormatting.components(from: hex) else {
                XCTFail("failed to parse \(hex)")
                continue
            }
            if comp.r != value { wrong.append(value) }
        }
        XCTAssertTrue(wrong.isEmpty, "\(wrong.count)/256 channel values are wrong: \(wrong.prefix(10))")
    }

    /// What the HEX row shows and what the Copy-HEX button copies must be the
    /// same string — they are two renderings of one value.
    func testDisplayedHexMatchesTheCopiedHex() {
        for source in ["#0B0C0D", "#101112", "#242526", "#0A84FF", "#FFFFFF", "#000000"] {
            let copied = ColorFormatting.hex(from: source)
            XCTAssertEqual(copied?.uppercased(), source.uppercased(),
                           "Copy-HEX must reproduce the source exactly")

            guard let comp = ColorFormatting.components(from: source) else {
                XCTFail("failed to parse \(source)"); continue
            }
            let displayed = String(format: "#%02X%02X%02X", comp.r, comp.g, comp.b)
            XCTAssertEqual(displayed.uppercased(), source.uppercased(),
                           "the HEX row must show the source colour, not a truncated one")
        }
    }

    /// Pins the trap itself, because the tests above pass either way: they
    /// exercise `ColorFormatting`, which was always correct. The bug was the
    /// preview re-deriving channels from the parsed `Color` via NSColor, whose
    /// extended-sRGB components come back as 10.999997 for an exact 11 — so
    /// `Int()` floored 75 of 256 values. If anyone reintroduces that round
    /// trip, this test says why it cannot work.
    func testTheNSColorRoundTripIsLossyAndMustNotBeUsedForDisplay() {
        var truncated: [Int] = []
        for value in 0...255 {
            let color = Color(.sRGB,
                              red: Double(value) / 255.0,
                              green: Double(value) / 255.0,
                              blue: Double(value) / 255.0,
                              opacity: 1)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            NSColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            if Int(r * 255) != value { truncated.append(value) }
        }
        XCTAssertFalse(truncated.isEmpty,
                       "if this ever becomes lossless the guard below can be relaxed")

        // Rounding survives the same round trip where truncation does not.
        for value in truncated {
            let color = Color(.sRGB,
                              red: Double(value) / 255.0,
                              green: Double(value) / 255.0,
                              blue: Double(value) / 255.0,
                              opacity: 1)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            NSColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(Int((r * 255).rounded()), value)
        }
    }

    /// The rows the panel renders must carry the copied colour.
    func testRenderedRowsShowTheSourceColour() throws {
        let comp = try XCTUnwrap(ColorFormatting.components(from: "#0B0C0D"))
        let rows = ColorPreviewFormats.rows(for: comp)

        XCTAssertEqual(rows.first(where: { $0.name == "HEX" })?.value.uppercased(), "#0B0C0D")
        XCTAssertEqual(rows.first(where: { $0.name == "RGB" })?.value, "11 12 13")
    }

    /// Alpha sources keep their channels in every row.
    func testRenderedRowsWithAlpha() throws {
        let comp = try XCTUnwrap(ColorFormatting.components(from: "rgba(10, 132, 255, 0.5)"))
        let rows = ColorPreviewFormats.rows(for: comp)

        XCTAssertEqual(rows.first(where: { $0.name == "HEX" })?.value.uppercased(), "#0A84FF")
        XCTAssertEqual(rows.first(where: { $0.name == "RGB" })?.value, "10 132 255")
        XCTAssertEqual(rows.first(where: { $0.name == "RGBA" })?.value, "10 132 255 0.50")
    }

    /// The RGB row must report the copied channel values.
    func testRGBRowReportsTheSourceChannels() throws {
        let comp = try XCTUnwrap(ColorFormatting.components(from: "#0B0C0D"))
        XCTAssertEqual(comp.r, 11)
        XCTAssertEqual(comp.g, 12)
        XCTAssertEqual(comp.b, 13)
    }

    /// rgba() sources keep their channels too.
    func testRGBASourceKeepsItsChannels() throws {
        let comp = try XCTUnwrap(ColorFormatting.components(from: "rgba(10, 132, 255, 0.5)"))
        XCTAssertEqual(comp.r, 10)
        XCTAssertEqual(comp.g, 132)
        XCTAssertEqual(comp.b, 255)
    }
}

/// JSON tree mode rendered the integer 1 as `true` and 0 as `false`.
///
/// `JSONSerialization` returns every number as an `NSNumber`, and
/// `NSNumber(1) as? Bool` succeeds — so testing `as? Bool` before `as? NSNumber`
/// converted counters and flags into booleans, coloured like real ones. The
/// formatted and minified tabs showed the same document correctly, so one item
/// read two different ways depending on the selected tab.
final class JSONValueRenderingTests: XCTestCase {
    private func parse(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    func testIntegerOneIsNotABoolean() throws {
        let object = try parse(#"{"count": 1, "zero": 0, "two": 2, "flag": true}"#)
        let dict = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(JSONValueRendering.describe(dict["count"] as Any), .number("1"))
        XCTAssertEqual(JSONValueRendering.describe(dict["zero"] as Any), .number("0"))
        XCTAssertEqual(JSONValueRendering.describe(dict["two"] as Any), .number("2"))
        XCTAssertEqual(JSONValueRendering.describe(dict["flag"] as Any), .boolean("true"),
                       "a real boolean must still render as one")
    }

    func testArrayOfOnesAndZeroesStaysNumeric() throws {
        let array = try XCTUnwrap(try parse("[0, 1, 2, 1]") as? [Any])
        let rendered = array.map { JSONValueRendering.describe($0) }
        XCTAssertEqual(rendered, [.number("0"), .number("1"), .number("2"), .number("1")])
    }

    func testStringsNullAndFloatsAreUnaffected() throws {
        let object = try parse(#"{"s": "hi", "n": null, "f": 1.5, "neg": -3}"#)
        let dict = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(JSONValueRendering.describe(dict["s"] as Any), .string("hi"))
        XCTAssertEqual(JSONValueRendering.describe(dict["n"] as Any), .null)
        XCTAssertEqual(JSONValueRendering.describe(dict["f"] as Any), .number("1.5"))
        XCTAssertEqual(JSONValueRendering.describe(dict["neg"] as Any), .number("-3"))
    }

    func testBothBooleanLiteralsRenderAsBooleans() throws {
        let object = try parse(#"{"t": true, "f": false}"#)
        let dict = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(JSONValueRendering.describe(dict["t"] as Any), .boolean("true"))
        XCTAssertEqual(JSONValueRendering.describe(dict["f"] as Any), .boolean("false"))
    }
}
