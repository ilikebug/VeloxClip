import XCTest
@testable import VeloxClip

/// Round-4 findings against the round-3 markdown chunker rewrite.
///
/// The rewrite fixed fence preservation but introduced: a quadratic blow-up on
/// loose lists, a blank-line suppression that welds unrelated blocks together,
/// a year/version false positive, and it left `~~~` fences unhandled — the very
/// bug it set out to fix, for the other fence syntax.
final class MarkdownChunkerRound4Tests: XCTestCase {

    // MARK: - Cost

    /// `bufferIsAList()` re-split the whole accumulated buffer on every blank
    /// line, so a loose list cost O(k·n). Measured 8.2s for 4000 items where
    /// the pre-rewrite chunker took 0.006s.
    func testALooseListChunksInLinearTime() {
        func cost(items: Int) -> TimeInterval {
            let doc = (1...items).map { "\($0). item \($0)\n" }.joined(separator: "\n")
            let start = Date()
            _ = MarkdownView.chunk(doc)
            return Date().timeIntervalSince(start)
        }

        _ = cost(items: 200) // warm up
        let small = cost(items: 1000)
        let large = cost(items: 4000)

        XCTAssertLessThan(large, 1.0,
                          "4000-item loose list took \(large)s")
        // 4x the input must not cost dramatically more than 4x the time.
        XCTAssertLessThan(large, max(small * 10, 0.5),
                          "growth is super-linear: 1000=\(small)s 4000=\(large)s")
    }

    func testARealisticMarkdownDocumentChunksFast() {
        let block = """
        ## Section

        - first point
        - second point

        Some prose that follows the list and explains it.

        ```swift
        let x = 1
        ```

        """
        let doc = String(repeating: block, count: 400) // ~50 KB

        let start = Date()
        _ = MarkdownView.chunk(doc)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.25,
                          "a 50 KB markdown item took \(elapsed)s; the preview is blank that long")
    }

    // MARK: - Boundaries

    /// A list must not absorb the paragraph that follows it.
    func testAListIsNotWeldedToTheFollowingParagraph() {
        let chunks = MarkdownView.chunk("""
        - alpha

        Unrelated paragraph about something else.

        A third paragraph.
        """).map(\.content)

        XCTAssertFalse(chunks.contains { $0.contains("alpha") && $0.contains("Unrelated") },
                       "the list and the next paragraph must not be one chunk, got \(chunks)")
    }

    /// Prose that merely begins with a number is not a list.
    func testASentenceStartingWithAYearIsNotAListItem() {
        let chunks = MarkdownView.chunk("""
        He opened the book.
        1984. It was a bright cold day in April.

        A completely separate paragraph.
        """).map(\.content)

        XCTAssertFalse(chunks.contains { $0.contains("1984") && $0.contains("separate paragraph") },
                       "a year sentence must not swallow the next paragraph, got \(chunks)")
    }

    /// The loose list itself must still survive as one document.
    func testALooseListStillStaysOneDocument() {
        let chunks = MarkdownView.chunk("""
        1. first

        2. second

        3. third
        """).map(\.content)

        let listChunks = chunks.filter {
            $0.contains("first") || $0.contains("second") || $0.contains("third")
        }
        XCTAssertEqual(listChunks.count, 1, "got \(listChunks)")
    }

    func testANestedLooseListStaysOneDocument() {
        let chunks = MarkdownView.chunk("""
        - outer

          - inner one

          - inner two
        """).map(\.content)

        let listChunks = chunks.filter { $0.contains("outer") || $0.contains("inner") }
        XCTAssertEqual(listChunks.count, 1, "got \(listChunks)")
    }

    // MARK: - Tilde fences

    /// CommonMark allows `~~~` fences. They must protect their content just
    /// like backtick fences do.
    func testTildeFenceProtectsItsContent() {
        let chunks = MarkdownView.chunk("""
        ~~~
        # include <stdio.h>
        int main() {}
        ~~~
        """).map(\.content)

        XCTAssertFalse(chunks.contains { $0.trimmingCharacters(in: .whitespaces) == "# include <stdio.h>" },
                       "a # line inside a ~~~ fence must not become a heading, got \(chunks)")
        XCTAssertTrue(chunks.contains { $0.contains("int main()") && $0.hasPrefix("~~~") },
                      "the tilde fence must reach the renderer, got \(chunks)")
    }

    /// A tilde inside a backtick block is content, not a fence.
    func testMismatchedFenceCharacterDoesNotCloseTheBlock() {
        let chunks = MarkdownView.chunk("""
        ```
        ~~~ this is just text
        still inside
        ```
        """).map(\.content)

        XCTAssertEqual(chunks.count, 1, "the block must stay whole, got \(chunks)")
        XCTAssertTrue(chunks[0].contains("still inside"))
    }

    // MARK: - CRLF

    /// CRLF is split by `.newlines` as two separators, injecting a blank line
    /// between every source line. Now that fences survive, that double-spaces
    /// copied Windows code inside a real code block.
    func testCRLFCodeBlockIsNotDoubleSpaced() {
        let source = "```swift\r\nlet a = 1\r\nlet b = 2\r\n```"
        let chunks = MarkdownView.chunk(source).map(\.content)

        XCTAssertEqual(chunks.count, 1, "got \(chunks)")
        XCTAssertEqual(chunks[0], "```swift\nlet a = 1\nlet b = 2\n```")
    }

    func testCRLFProseChunksLikeLFProse() {
        let crlf = MarkdownView.chunk("first line\r\nsecond line\r\n\r\nnew paragraph").map(\.content)
        let lf = MarkdownView.chunk("first line\nsecond line\n\nnew paragraph").map(\.content)

        XCTAssertEqual(crlf, lf, "CRLF must chunk identically to LF")
        XCTAssertEqual(crlf.count, 2)
    }

    // MARK: - Invariants the rewrite must keep

    func testFencesStillSurviveWithTheirLanguageHint() {
        let chunks = MarkdownView.chunk("""
        ```swift
        let x = 1
        ```
        """).map(\.content)
        XCTAssertTrue(chunks.contains { $0.contains("```swift") && $0.contains("let x = 1") })
    }

    func testHeadingInsideAFenceIsNotPromoted() {
        let chunks = MarkdownView.chunk("""
        ```
        # not a heading
        ```
        """).map(\.content)
        XCTAssertEqual(chunks.count, 1, "got \(chunks)")
    }

    func testEveryNonBlankLineSurvivesExactlyOnce() {
        let doc = """
        # Title

        Intro paragraph.

        - one
        - two

        ```swift
        let x = 1
        ```

        1. step

        2. step two

        Closing words.
        """
        let joined = MarkdownView.chunk(doc).map(\.content).joined(separator: "\n")

        for line in doc.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            XCTAssertTrue(joined.contains(line.trimmingCharacters(in: .whitespaces)),
                          "lost line: \(line)")
        }
    }

    func testEmptyAndWhitespaceInputDoNotCrash() {
        XCTAssertEqual(MarkdownView.chunk("").count, 1)
        XCTAssertEqual(MarkdownView.chunk("   \n  \n").count, 1)
    }
}
