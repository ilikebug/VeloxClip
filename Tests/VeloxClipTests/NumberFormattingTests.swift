import XCTest
@testable import VeloxClip

/// Every count in the UI goes through `L10n.format(key, someInt)` against a
/// `%d` specifier. On 64-bit macOS `%d` consumes an Int32 while every call site
/// passes a 64-bit Swift Int, so any value at or above 2^31 renders as a
/// wrapped negative number. Nothing caps stored text length, and relativeTime
/// feeds raw second-intervals in, so this is reachable.
final class NumberFormattingTests: XCTestCase {

    func testLargeCountsRenderCorrectly() {
        let cases: [Int] = [0, 1, 2_147_483_647, 2_147_483_648, 3_000_000_000, 9_780_134_685]

        for value in cases {
            let rendered = L10n.format("row.unit.chars", value, language: .en)
            XCTAssertFalse(rendered.contains("-"),
                           "\(value) rendered as \(rendered)")
        }
    }

    func testTruncationNoticeSurvivesLargeCounts() {
        let rendered = L10n.format("detail.truncated", 3_000_000_000, language: .en)
        XCTAssertFalse(rendered.contains("-"), "got \(rendered)")
    }

    func testRelativeSecondsSurviveLargeIntervals() {
        let rendered = L10n.format("preview.datetime.secondsAgo", 4_000_000_000, language: .en)
        XCTAssertFalse(rendered.contains("-"), "got \(rendered)")
    }

    /// The specifier itself must be 64-bit in both languages, or this class of
    /// bug comes back with the next count someone adds.
    func testNoStringsFileUsesTheThirtyTwoBitSpecifier() throws {
        for language in ["en", "zh-Hans"] {
            let url = try XCTUnwrap(
                Bundle.module.url(forResource: "Localizable",
                                  withExtension: "strings",
                                  subdirectory: "\(language).lproj")
                ?? Bundle.module.url(forResource: "\(language).lproj/Localizable",
                                     withExtension: "strings")
            )
            let contents = try String(contentsOf: url, encoding: .utf8)

            // %d consumes 32 bits; Swift Int is 64. %ld is the correct one.
            let offenders = contents
                .components(separatedBy: "\n")
                .filter { $0.contains("%d") }

            XCTAssertTrue(offenders.isEmpty,
                          "\(language) still uses %d on \(offenders.count) line(s): \(offenders.prefix(3))")
        }
    }
}
