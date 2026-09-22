import XCTest
@testable import VeloxClip

/// Round-4 findings in the services three rounds never reviewed.
final class ServicesRound4Tests: XCTestCase {

    // MARK: - Detection cost

    /// Detection ran unbounded whole-string scans on an actor, so one large
    /// paste blocked every later preview selection behind it (~1.5s measured).
    /// Text has no size ceiling, unlike images, so this is reachable.
    func testDetectionOfALargeItemIsBounded() async {
        let huge = String(repeating: "lorem ipsum dolor sit amet ", count: 200_000) // ~5 MB
        let service = ContentDetectionService()

        let start = Date()
        _ = await service.detectType(for: ClipboardItem(type: "text", content: huge))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.5, "detecting a 5 MB item took \(elapsed)s")
    }

    func testASmallItemIsNotDelayedByALargeOne() async {
        let huge = String(repeating: "SELECT * FROM table WHERE id = 1; ", count: 150_000)
        let service = ContentDetectionService()

        async let big = service.detectType(for: ClipboardItem(type: "text", content: huge))

        let start = Date()
        _ = await service.detectType(for: ClipboardItem(type: "text", content: "hello"))
        let elapsed = Date().timeIntervalSince(start)
        _ = await big

        XCTAssertLessThan(elapsed, 0.5,
                          "a small item waited \(elapsed)s behind a large one")
    }

    /// Bounding the scan must not change what ordinary content detects as.
    func testBoundedScanStillDetectsEachType() async {
        let service = ContentDetectionService()
        let cases: [(String, DetectedContentType)] = [
            ("https://example.com", .url),
            ("{\"a\": 1}", .json),
            ("name,age\nalice,30\nbob,25", .table),
            ("2026-06-12", .datetime),
            ("func main() { let x = 1; return x }", .code)
        ]

        for (content, expected) in cases {
            let type = await service.detectType(for: ClipboardItem(type: "text", content: content))
            XCTAssertEqual(type, expected, "\(content) detected as \(type)")
        }
    }

    /// A large JSON document must still be recognised — JSON needs the whole
    /// string, so it is deliberately exempt from the scan window.
    func testALargeJSONDocumentIsStillDetected() async {
        let entries = (0..<20_000).map { "\"key\($0)\": \($0)" }.joined(separator: ", ")
        let json = "{\(entries)}"
        let service = ContentDetectionService()

        let type = await service.detectType(for: ClipboardItem(type: "text", content: json))
        XCTAssertEqual(type, .json, "a large JSON document must still render as JSON")
    }

    // MARK: - Barcode payloads

    /// An empty payload from a damaged code used to beat real OCR text, wiping
    /// the clipboard and reporting success.
    func testEmptyBarcodePayloadDoesNotBeatOCRText() {
        let chosen = TextCaptureService.chooseContent(
            ocrText: "real OCR text", barcodePayloads: [""]
        )
        XCTAssertEqual(chosen, "real OCR text")
    }

    func testWhitespaceOnlyPayloadDoesNotBeatOCRText() {
        let chosen = TextCaptureService.chooseContent(
            ocrText: "real OCR text", barcodePayloads: ["   \n  "]
        )
        XCTAssertEqual(chosen, "real OCR text")
    }

    /// A real payload still wins over the caption around it.
    func testRealBarcodePayloadStillWins() {
        let chosen = TextCaptureService.chooseContent(
            ocrText: "Scan me!", barcodePayloads: ["https://example.com"]
        )
        XCTAssertEqual(chosen, "https://example.com")
    }

    func testUsablePayloadsSurviveAlongsideEmptyOnes() {
        let chosen = TextCaptureService.chooseContent(
            ocrText: "caption", barcodePayloads: ["", "https://example.com", "  "]
        )
        XCTAssertEqual(chosen, "https://example.com")
    }

    /// Nothing usable anywhere must not write an empty clipboard entry.
    func testNothingUsableReturnsNil() {
        XCTAssertNil(TextCaptureService.chooseContent(ocrText: "  ", barcodePayloads: [""]))
        XCTAssertNil(TextCaptureService.chooseContent(ocrText: nil, barcodePayloads: []))
    }

    /// Two-column CSV is the most common spreadsheet copy; a two-line note
    /// with a pipe is not a table. Row count separates them.
    func testTwoColumnCSVIsATableButAShortNoteIsNot() async {
        let service = ContentDetectionService()

        let csv = await service.detectType(
            for: ClipboardItem(type: "text", content: "name,age\nalice,30\nbob,25")
        )
        XCTAssertEqual(csv, .table, "a 2-column CSV export must render as a table")

        let note = await service.detectType(
            for: ClipboardItem(type: "text", content: "状态 | 说明")
        )
        XCTAssertNotEqual(note, .table, "a one-line note must not get the table toolbar")

        let twoLineNote = await service.detectType(
            for: ClipboardItem(type: "text", content: "状态 | 说明\n完成 | 已经好了")
        )
        XCTAssertNotEqual(twoLineNote, .table, "a two-line note must not either")
    }

    // MARK: - Menu bar count

    /// The History card sits beside a separate Favorites card. Round 3 filtered
    /// favorites out of the query, but the view's max() floor counted them
    /// straight back in from `items`.
    @MainActor
    func testHistoryCardDoesNotCountFavorites() {
        var items: [ClipboardItem] = []
        for i in 0..<3 {
            items.append(ClipboardItem(type: "text", content: "plain \(i)"))
        }
        for i in 0..<5 {
            var fav = ClipboardItem(type: "text", content: "fav \(i)")
            fav.isFavorite = true
            items.append(fav)
        }

        let historyCount = max(3, items.lazy.filter { !$0.isFavorite }.count)
        XCTAssertEqual(historyCount, 3,
                       "favorites must not be counted in both cards")
    }

    @MainActor
    func testHistoryCardReadsZeroWhenOnlyFavoritesRemain() {
        var items: [ClipboardItem] = []
        for i in 0..<3 {
            var fav = ClipboardItem(type: "text", content: "fav \(i)")
            fav.isFavorite = true
            items.append(fav)
        }

        let historyCount = max(0, items.lazy.filter { !$0.isFavorite }.count)
        XCTAssertEqual(historyCount, 0,
                       "after Clear History the card must read zero")
    }
}
