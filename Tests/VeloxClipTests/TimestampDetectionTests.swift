import XCTest
@testable import VeloxClip

/// Any bare 10- or 13-digit number was classified as a unix timestamp and
/// rendered as a full calendar-date panel. ISBNs, order numbers, account and
/// tracking numbers all match that shape, so copying an ISBN produced a
/// confident eight-row panel claiming a date in 2279.
final class TimestampDetectionTests: XCTestCase {

    private func detectType(of content: String) async -> DetectedContentType {
        let item = ClipboardItem(type: "text", content: content)
        return await ContentDetectionService().detectType(for: item)
    }

    func testAnISBNIsNotADate() async {
        let type = await detectType(of: "9780134685991")
        XCTAssertNotEqual(type, .datetime,
                          "an ISBN-13 must not be shown as a date, got \(type)")
    }

    func testALongOrderNumberIsNotADate() async {
        // 13 digits starting with 9 is ~2255 as milliseconds — outside any
        // plausible epoch. (A 13-digit number that DOES fall in 2001-2033 as
        // milliseconds, e.g. 1234567890123, is genuinely indistinguishable
        // from a real timestamp; no heuristic can separate those.)
        let type = await detectType(of: "9876543210987")
        XCTAssertNotEqual(type, .datetime, "got \(type)")
    }

    func testAPhoneLikeTenDigitNumberIsNotADate() async {
        // 1e10 seconds is year 2286 — far outside anything a user copies.
        let type = await detectType(of: "9876543210")
        XCTAssertNotEqual(type, .datetime, "got \(type)")
    }

    /// Real timestamps must still be recognised.
    func testAPlausibleSecondTimestampIsStillADate() async {
        let now = Int(Date().timeIntervalSince1970)
        let type = await detectType(of: "\(now)")
        XCTAssertEqual(type, .datetime, "got \(type)")
    }

    func testAPlausibleMillisecondTimestampIsStillADate() async {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let type = await detectType(of: "\(now)")
        XCTAssertEqual(type, .datetime, "got \(type)")
    }

    func testFormattedDatesAreUnaffected() async {
        for sample in ["2026-06-12", "2026-06-12T14:30:00Z", "14:30", "12/06/2026"] {
            let type = await detectType(of: sample)
            XCTAssertEqual(type, .datetime, "\(sample) must still be a date")
        }
    }
}

/// The datetime preview divided a 13-digit millisecond value by 1000 to build a
/// Date, then rendered and copied back the SECONDS value — handing the user a
/// number 1000x smaller than the one they copied.
final class UnixTimestampRoundTripTests: XCTestCase {

    func testCopyUnixReturnsTheMillisecondValueItWasGiven() {
        let source = "1718200000123"
        let copied = DateTimePreviewPresentation.unixTimestampString(for: source)
        XCTAssertEqual(copied, source,
                       "a millisecond timestamp must round-trip unchanged")
    }

    func testCopyUnixReturnsTheSecondValueItWasGiven() {
        let source = "1718200000"
        let copied = DateTimePreviewPresentation.unixTimestampString(for: source)
        XCTAssertEqual(copied, source)
    }

    /// A formatted date has no original epoch to preserve, so it renders the
    /// seconds value — that path is unchanged.
    func testAFormattedDateStillProducesSeconds() throws {
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-06-12T14:30:00Z")
        )
        let rendered = DateTimePreviewPresentation.unixTimestampString(
            for: "2026-06-12T14:30:00Z", parsedDate: date
        )
        XCTAssertEqual(rendered, "\(Int(date.timeIntervalSince1970))")
    }
}
