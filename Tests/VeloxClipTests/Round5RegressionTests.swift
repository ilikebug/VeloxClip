import XCTest
@testable import VeloxClip

/// Round-6 findings against the round-5 fixes. Nine regressions f5b2bba
/// introduced, each proven to pass at f5b2bba^.
final class Round5RegressionTests: XCTestCase {

    private func chunk(_ text: String) -> [String] {
        MarkdownView.chunk(text).map(\.content)
    }

    // MARK: - Chunker: the fence scan is quadratic again

    /// `isOpeningFence` scans the rest of the document for a closer on every
    /// fence-looking line. Descending divider lengths defeat the short-circuit,
    /// which is round 3's quadratic bug in a new place: 34s at 2000 dividers.
    func testDescendingDividerRunsStayLinear() {
        var lines: [String] = []
        for length in stride(from: 2_100, to: 100, by: -1) {
            lines.append(String(repeating: "~", count: max(3, length % 200 + 3)))
            lines.append("prose line")
        }
        let doc = lines.joined(separator: "\n")

        let start = Date()
        _ = chunk(doc)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "\(lines.count) descending fence runs took \(elapsed)s")
    }

    // MARK: - Chunker: a list with a lead-in line

    /// `chunkStartsAList` only looks at the chunk's FIRST line, so any list
    /// introduced by a lead-in sentence lost the blank-line hold-open rule —
    /// and MarkdownUI restarts the numbering at 1 for each fragment. This is
    /// the exact failure rounds 3, 4 and 5 each set out to prevent.
    func testLeadInSentenceBeforeAListHoldsTheListTogether() {
        let doc = "Here are the steps:\n1. Install the tool\n2. Run the setup\n\n3. Verify the output"
        XCTAssertEqual(chunk(doc).count, 1, "the list split, so the numbering restarts; got \(chunk(doc))")
    }

    func testLeadInWithIndentedContinuationHoldsTogether() {
        let doc = "To deploy, do this:\n1. Push the branch\n\n   It takes about a minute.\n2. Merge the PR"
        XCTAssertEqual(chunk(doc).count, 1, "got \(chunk(doc))")
    }

    func testBoldLeadInBeforeAList() {
        let doc = "**Steps:**\n- alpha\n- beta\n\n- gamma"
        XCTAssertEqual(chunk(doc).count, 1, "got \(chunk(doc))")
    }

    /// The prose case the flag was added for must still be rejected: a sentence
    /// starting "1) " with no list above it in the chunk is not a list.
    func testParenNumberProseStillDoesNotGlueTheNextList() {
        let doc = """
        The statute is section 12 subsection 3) which applies here.
        1) is also how the German ordinal is written in this sentence.

        1) real first
        2) real second
        """
        XCTAssertGreaterThan(chunk(doc).count, 1, "prose must not be welded to the list; got \(chunk(doc))")
    }

    /// Round 5 capped `N) ` at 2 digits, so a real paren list broke at item 100.
    func testParenListSurvivesPastItemNinetyNine() {
        let doc = (98...103).map { "\($0)) item\n" }.joined(separator: "\n")
        XCTAssertEqual(chunk(doc).count, 1, "a 3-digit paren list fragmented; got \(chunk(doc).count) chunks")
    }

    // MARK: - Chunker: the two halves of the fence logic disagree

    /// The forward scan requires a closer to have an empty info string; the
    /// branch that actually closes accepted any run. A block therefore closed
    /// on a nested ```lang line, and chunking stopped being idempotent.
    func testNestedFenceWithAnInfoStringDoesNotCloseTheOuterBlock() {
        let doc = "````\nHere is how you write a Swift block:\n```swift\nlet x = 1\n```\n````\n\nAfter the block."
        let chunks = chunk(doc)
        XCTAssertTrue(
            chunks.contains { $0.contains("let x = 1") && $0.hasPrefix("````") },
            "the outer block lost its body; got \(chunks)"
        )
    }

    func testChunkingIsIdempotent() {
        let docs = [
            "```\nbody\n```swift",
            "```\n\n1. numbered item\n```swift",
            "# Title\n\n```py\nx = 1\n```\n\n- a\n- b",
            "~~~\ncode\n~~~\n\nprose",
        ]
        for doc in docs {
            let once = chunk(doc)
            let twice = once.flatMap { chunk($0) }
            XCTAssertEqual(once, twice, "chunking is not idempotent for \(doc.debugDescription)")
        }
    }

    /// A shorter run must not close a longer fence (CommonMark).
    func testShorterRunDoesNotCloseALongerFence() {
        let doc = "````\nline one\n```\nline two\n````"
        let chunks = chunk(doc)
        XCTAssertTrue(chunks.contains { $0.contains("line one") && $0.contains("line two") },
                      "the 3-backtick line must not close a 4-backtick fence; got \(chunks)")
    }

    // MARK: - FIFOCache: eviction discards the value just written

    /// Overwriting the OLDEST key with a value that exceeds the budget evicted
    /// exactly the entry just written — so the preview caches were useless for
    /// precisely the large documents they were bounded for.
    func testOverwritingTheOldestKeyKeepsTheValueJustWritten() {
        var cache = FIFOCache<String, String>(maxEntries: 10, maxBytes: 1000) { key, value in
            key.utf8.count + value.utf8.count
        }
        cache["old"] = "small"
        cache["new"] = "small"
        cache["old"] = String(repeating: "x", count: 1500)

        XCTAssertNotNil(cache["old"], "the value just written was evicted; every lookup re-parses the document")
    }

    func testOverwriteUnderBudgetKeepsBothEntries() {
        var cache = FIFOCache<String, String>(maxEntries: 10, maxBytes: 1000) { key, value in
            key.utf8.count + value.utf8.count
        }
        cache["a"] = "one"
        cache["b"] = "two"
        cache["a"] = "three"
        XCTAssertNotNil(cache["a"])
        XCTAssertNotNil(cache["b"])
    }

    // MARK: - Detection: the table guard

    /// The space test is document-global and disqualifying, so one summary row
    /// demoted a 52-row export.
    func testOnePaddedCellDoesNotDisqualifyALongExport() async {
        var rows = ["name,amount"]
        for i in 0..<50 { rows.append("row\(i),\(i * 99)") }
        rows.append("total, 4950")
        let item = ClipboardItem(type: "text", content: rows.joined(separator: "\n"))
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertEqual(type, .table, "one padded cell out of 52 rows disqualified the export, got \(type)")
    }

    /// …while the two-line hand-typed note the guard exists for stays rejected.
    func testTightTwoLineNoteIsNotATable() async {
        let item = ClipboardItem(type: "text", content: "状态|说明\n完成|已发布")
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertNotEqual(type, .table, "a two-line hand-typed note rendered as a table")
    }

    func testTightThreeRowExportIsStillATable() async {
        let item = ClipboardItem(type: "text", content: "name,age\nAlice,30\nBob,25")
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertEqual(type, .table, "got \(type)")
    }

    // MARK: - Detection: the epoch ceiling

    /// Widening to 4.1e9 tripled the 10-digit space classed as a date, catching
    /// every US phone number probe.
    func testTenDigitPhoneNumbersAreNotDates() async {
        for number in ["2125550199", "3105550143", "4085550111", "2065550188"] {
            let item = ClipboardItem(type: "text", content: number)
            let type = await ContentDetectionService.shared.detectType(for: item)
            XCTAssertNotEqual(type, .datetime, "\(number) renders as a date, got \(type)")
        }
    }

    func testTenDigitOrderNumberIsNotADate() async {
        let item = ClipboardItem(type: "text", content: "3000123456")
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertNotEqual(type, .datetime, "got \(type)")
    }

    /// The constant the widening was for must still work.
    func testINT32MaxIsStillADate() async {
        let item = ClipboardItem(type: "text", content: "2147483647")
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertEqual(type, .datetime, "INT32_MAX must still be a date, got \(type)")
    }

    func testCurrentEpochIsStillADate() async {
        let item = ClipboardItem(type: "text", content: "1758518400")
        let type = await ContentDetectionService.shared.detectType(for: item)
        XCTAssertEqual(type, .datetime, "got \(type)")
    }

    // MARK: - Ingestion: the whitespace guard drops real payloads

    /// The guard returns `.none` for the whole payload from inside the text
    /// branch, so it never falls through to rtf/image. PasteboardService nils
    /// rtf/image whenever a .string flavour exists, so an app advertising a
    /// whitespace plain-text flavour beside a screenshot lost the screenshot.
    func testWhitespaceTextAlongsideAnImageKeepsTheImage() {
        let payload = PasteboardPayload(text: "  \n ", image: Data([0x89, 0x50, 0x4E, 0x47]))
        let kind = IngestionPipeline.classify(payload)
        if case .none = kind {
            XCTFail("a real image copy was discarded because its plain-text flavour was whitespace")
        }
    }

    func testWhitespaceTextAlongsideRTFKeepsTheRTF() {
        let payload = PasteboardPayload(text: "   ", rtf: Data([0x7B, 0x5C, 0x72, 0x74]))
        let kind = IngestionPipeline.classify(payload)
        if case .none = kind {
            XCTFail("a real RTF paste was discarded because its plain-text flavour was whitespace")
        }
    }

    /// A genuinely text-only whitespace copy is still dropped.
    func testWhitespaceOnlyTextIsStillDropped() {
        for blank in ["\n", "\t", "    ", "\n\n"] {
            let kind = IngestionPipeline.classify(PasteboardPayload(text: blank))
            guard case .none = kind else {
                return XCTFail("whitespace-only text became \(kind)")
            }
        }
    }
}
