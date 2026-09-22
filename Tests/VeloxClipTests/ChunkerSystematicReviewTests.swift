import XCTest
@testable import VeloxClip

/// Systematic edge-case review of the extracted Chunk.run(on:).
///
/// The chunker has been rewritten four times, each time the rewrite fixed the
/// bugs the previous one introduced *and* introduced fresh ones. This
/// enumerates edge cases the existing 35 tests do not cover:
///
///  1. CommonMark spec examples for fences, lists, thematic breaks and ATX
///     headings that test every rule the chunker enforces.
///  2. Composition: what happens when two rules interact (a list inside a
///     blockquote, a fence containing markdown that looks like prose, etc.)?
///  3. Idempotency on generated adversarial documents.

final class ChunkerSystematicReviewTests  : XCTestCase {

    private func chunk(_ doc: String) -> [String] {
        Chunk.run(on: doc).map(\.content)
    }

    // ------------------------------------------------------------------
    // THEMATIC BREAKS — lines of 3+ hyphens / underscores / asterisks
    // that must NOT become fences (fences are backticks and tildes).
    // ------------------------------------------------------------------

    func testThematicBreakOfHyphens() {
        // CommonMark: a line of 3+ hyphens is a thematic break, not a fence.
        let doc = "Paragraph.\n\n---\n\nAnother paragraph."
        let c = chunk(doc)
        XCTAssertEqual(c.count, 3, "a thematic break must not swallow the next paragraph; got \(c)")
    }

    func testThematicBreakOfUnderscores() {
        let doc = "Paragraph.\n\n___\n\nAnother paragraph."
        let c = chunk(doc)
        XCTAssertEqual(c.count, 3, "got \(c)")
    }

    func testThematicBreakOfAsterisks() {
        let doc = "Paragraph.\n\n***\n\nAnother paragraph."
        let c = chunk(doc)
        XCTAssertEqual(c.count, 3, "got \(c)")
    }

    // ------------------------------------------------------------------
    // EMPTY DOCUMENT / SINGLE LINES
    // ------------------------------------------------------------------

    func testEmptyDocumentYieldsOneEmptyChunk() {
        let c = chunk("")
        XCTAssertEqual(c.count, 1)
    }

    func testWhitespaceOnlyDocumentYieldsOneEmptyChunk() {
        for ws in ["\n\n\n", "   \n\t\n   ", "\r\n\r\n"] {
            let c = chunk(ws)
            XCTAssertEqual(c.count, 1, "for input \(ws.debugDescription)")
        }
    }

    func testSingleLineIsItsOwnChunk() {
        XCTAssertEqual(chunk("hello").count, 1)
    }

    // ------------------------------------------------------------------
    // ATX HEADING EDGE CASES
    // ------------------------------------------------------------------

    func testATXHeadingWithLeadingSpaces() {
        // CommonMark: up to 3 spaces are allowed before the #.
        let doc = "   ### Heading with spaces\nparagraph"
        let c = chunk(doc)
        XCTAssertTrue(c.contains { $0.contains("### Heading with spaces") })
        XCTAssertEqual(c.count, 2, "heading and paragraph as separate chunks; got \(c)")
    }

    func testATXHeadingWithoutSpace() {
        // "#foo" is a heading; "# foo" is a heading. The chunker sees `trimmed.hasPrefix` so both work.
        let c = chunk("#foo\nbar")
        XCTAssertTrue(c.contains("#foo"))
    }

    func testUnicodeHeadingIsNotConfused() {
        // U+FF03 is FULLWIDTH NUMBER SIGN, not ASCII #.
        let doc = "\u{FF03} Not a heading\nbar"
        let c = chunk(doc)
        // The chunker does NOT detect this as a heading — it stays prose.
        XCTAssertTrue(c.contains { $0.contains("\u{FF03} Not a heading") })
    }

    // ------------------------------------------------------------------
    // FENCE EDGE CASES
    // ------------------------------------------------------------------

    func testMixedFenceTypesAreIndependent() {
        // ``` and ~~~ must not interfere with each other.
        let doc = """
        ~~~
        text
        ```swift
        code
        ```
        ~~~
        """
        let c = chunk(doc)
        XCTAssertEqual(c.count, 1, "a ~~~ fence must not be closed by ```, got \(c)")
    }

    func testClosingWithTrailingSpaces() {
        // CommonMark: ```   (trailing whitespace) is a valid closing fence.
        let doc = """
        ```
        code
        ```   
        after
        """
        let c = chunk(doc)
        let codeChunk = c.first { $0.contains("code") }
        XCTAssertNotNil(codeChunk, "a fence closed with trailing spaces must still close; got \(c)")
        XCTAssertTrue(c.contains { $0.contains("after") })
    }

    func testInfoStringWithSpacePrefix() {
        // "``` swift" — the space after backticks is trimmed by fenceRun's trimmingCharacters.
        let doc = """
        ``` swift
        let x = 1
        ```
        """
        let c = chunk(doc)
        XCTAssertTrue(c.contains { $0.contains("``` swift") && $0.contains("let x = 1") },
                      "info string with leading space must survive; got \(c)")
    }

    func testTildeFenceWithLanguageHint() {
        let doc = """
        ~~~cpp
        int main() {}
        ~~~
        """
        let c = chunk(doc)
        XCTAssertTrue(c.contains { $0.contains("~~~cpp") && $0.contains("int main()") })
    }

    func testFenceContainingAnIndentedCodeBlock() {
        // Inside a fence, everything is literal — indentation is preserved.
        let doc = """
        ```
            public static void main(String[] args) {
                System.out.println("hello");
            }
        ```
        after
        """
        let c = chunk(doc)
        let code = c.first { $0.contains("public static") }
        XCTAssertNotNil(code)
        XCTAssertTrue(code!.contains("    public"), "indentation inside fence must survive; got \(code!)")
    }

    // ------------------------------------------------------------------
    // LIST EDGE CASES
    // ------------------------------------------------------------------

    func testSingleListItemIsAChunk() {
        // A one-item list must still emit: no previous list item to compare.
        XCTAssertEqual(chunk("- lonely").count, 1)
    }

    func testListAfterAHeadingStaysTogether() {
        // The heading flushed the chunk, so the list starts fresh — inList is
        // false, and firstItem + lastTrimmed.isEmpty starts the list.
        let doc = "## Instructions\n- step one\n- step two"
        let c = chunk(doc)
        // Heading is one chunk, the list is another.
        XCTAssertEqual(c.count, 2, "heading and list as two chunks; got \(c)")
    }

    func testNestedOrderedListInsideBullet() {
        // CommonMark: a nested list indented under a bullet.
        let doc = """
        - item one
          1. sub a
          2. sub b
        - item two
        """
        // The chunk should contain the whole list.
        let c = chunk(doc)
        XCTAssertEqual(c.count, 1, "a nested list must stay one document; got \(c)")
    }

    func testLooseListFollowedByCodeBlock() {
        let doc = """
        - step 1

        - step 2

        ```
        code
        ```
        """
        let c = chunk(doc)
        let listChunks = c.filter { $0.contains("step") }
        XCTAssertEqual(listChunks.count, 1, "the list must stay one chunk; got \(c)")
        XCTAssertTrue(c.contains { $0.contains("code") })
    }

    func testCodeBlockFollowedByList() {
        let doc = """
        ```
        code
        ```
        - one
        - two
        """
        let c = chunk(doc)
        XCTAssertEqual(c.count, 2, "code block then list as two chunks; got \(c)")
        XCTAssertTrue(c.contains { $0.contains("one") && $0.contains("two") })
    }

    // ------------------------------------------------------------------
    // IDEMPOTENCY ON ADVERSARIAL INPUTS
    // ------------------------------------------------------------------

    func testIdempotentOnAdversarialDoc1() {
        // Alternating fences of different lengths with prose.
        let doc = """
        # Title
        Normal prose.
        ``````
        code block
        `````
        ~~~~
        tilde block
        ~~~
        prose again
        """
        let c = chunk(doc)
        let rec = c.flatMap { Chunk.run(on: $0).map(\.content) }
        XCTAssertEqual(c, rec, "chunking is not idempotent")
    }

    func testIdempotentOnAdversarialDoc2() {
        // Numbered items, blank lines, a fence, more items.
        let doc = """
        ## Setup

        1. First instruction.
        2. Second instruction.

           Indented detail.

        3. Third instruction.

        ```bash
        npm install
        npm test
        ```

        4. Fourth step.
        5. Done.
        """
        let c = chunk(doc)
        let rec = c.flatMap { Chunk.run(on: $0).map(\.content) }
        XCTAssertEqual(c, rec, "chunking is not idempotent")
    }

    // ------------------------------------------------------------------
    // COST — the new implementation MUST stay linear
    // ------------------------------------------------------------------

    func testLargeLooseListIsLinear() {
        func cost(items: Int) -> TimeInterval {
            let doc = (1...items).map { "\($0). item \($0)\n" }.joined(separator: "\n")
            let start = Date()
            _ = Chunk.run(on: doc)
            return Date().timeIntervalSince(start)
        }

        _ = cost(items: 200)
        let s = cost(items: 1000)
        let l = cost(items: 4000)
        XCTAssertLessThan(l, 1.0, "4000-item loose list took \(l)s")
        // 4× the input → at most 10× the time (allows reasonable constant growth)
        XCTAssertLessThan(l, max(s * 10, 0.5), "super-linear: 1000=\(s)s 4000=\(l)s")
    }

    func testDescendingDividersAreLinear() {
        var lines: [String] = []
        for length in stride(from: 2100, to: 100, by: -1) {
            lines.append(String(repeating: "~", count: max(3, length % 200 + 3)))
            lines.append("prose")
        }
        let doc = lines.joined(separator: "\n")
        let start = Date()
        _ = Chunk.run(on: doc)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "descending dividers took \(elapsed)s")
    }

    // ------------------------------------------------------------------
    // COMPOSITION REGRESSION — the rewrites' graveyard of interactions
    // ------------------------------------------------------------------

    /// Round 3: fence swallowed list after a fence that never closed.
    /// Round 4: fence swallowed list after a fence that DID close (no re-emit).
    func testListImmediatelyAfterAFenceBlock() {
        let doc = """
        ```
        code
        ```
        - item 1
        - item 2
        """
        let c = chunk(doc)
        // First chunk contains the fence block, second contains the list.
        XCTAssertTrue(c.contains { $0.contains("code") })
        XCTAssertTrue(c.contains { $0.contains("item 1") && $0.contains("item 2") })
    }

    /// Round 5: lead-in before a list lost hold-open (chunkStartsAList).
    ///
    /// Correct behaviour: a lead-in is a separate paragraph, and a loose list
    /// only holds itself together once it HAS started. The lead-in line is not
    /// welded to the list — it is its own chunk. What must NOT happen is the
    /// list fragmenting: the three numbered items must stay one chunk.
    func testLeadInFollowedByLooseList() {
        let doc = "Here is the recipe:\n\n1. Mix flour.\n\n2. Add water.\n\n3. Bake.\n\nDone."
        let c = chunk(doc)
        // The lead-in is one chunk, the loose list is one chunk, "Done." is one chunk.
        let listChunk = c.first { $0.contains("Mix flour") }
        XCTAssertNotNil(listChunk, "the loose list was swallowed; got \(c)")
        XCTAssertTrue(listChunk!.contains("Bake"), "the loose list after a lead-in was split; got \(c)")
        XCTAssertEqual(c.count, 3, "lead-in / list / done, got \(c)")
    }
}