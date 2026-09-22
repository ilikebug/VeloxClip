import XCTest
@testable import VeloxClip

/// The chunker splits long documents so they can render incrementally. It must
/// not change what the document *is*.
///
/// It consumed ``` fence lines with `continue` and never re-emitted them, so a
/// code block arrived at MarkdownUI as bare prose: newlines collapsed, no
/// monospace, no background — and the ~110 lines of codeBlock styling could
/// never fire. For a clipboard manager holding copied code, that is the
/// preview that matters most.
final class MarkdownChunkingTests: XCTestCase {

    func testFencedCodeBlockKeepsItsFences() {
        let source = """
        Intro line.

        ```swift
        let x = 1
        print(x)
        ```

        Outro line.
        """
        let chunks = MarkdownView.chunk(source).map(\.content)

        let codeChunk = chunks.first { $0.contains("let x = 1") }
        XCTAssertNotNil(codeChunk, "the code must survive chunking")
        XCTAssertTrue(codeChunk?.hasPrefix("```") == true,
                      "the opening fence must reach the renderer, got: \(codeChunk ?? "nil")")
        XCTAssertTrue(codeChunk?.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("```") == true,
                      "the closing fence must reach the renderer, got: \(codeChunk ?? "nil")")
    }

    func testCodeBlockKeepsItsLanguageHint() {
        let chunks = MarkdownView.chunk("""
        ```swift
        let x = 1
        ```
        """).map(\.content)

        XCTAssertTrue(chunks.contains { $0.contains("```swift") },
                      "the language hint drives syntax highlighting")
    }

    func testIndentationInsideACodeBlockSurvives() {
        let chunks = MarkdownView.chunk("""
        ```
        func f() {
            return 1
        }
        ```
        """).map(\.content)

        let code = chunks.first { $0.contains("func f()") }
        XCTAssertTrue(code?.contains("    return 1") == true,
                      "indentation must not be collapsed")
    }

    /// A blank line inside a loose list must not split it into independent
    /// documents — each would restart its own numbering and lose list context.
    func testLooseListStaysOneDocument() {
        let source = """
        1. first

        2. second

        3. third
        """
        let chunks = MarkdownView.chunk(source).map(\.content)
        let listChunks = chunks.filter { $0.contains("first") || $0.contains("second") || $0.contains("third") }

        XCTAssertEqual(listChunks.count, 1,
                       "a loose list must stay one document, got \(listChunks.count): \(listChunks)")
    }

    func testUnorderedLooseListStaysOneDocument() {
        let source = """
        - alpha

        - beta
        """
        let chunks = MarkdownView.chunk(source).map(\.content)
        let listChunks = chunks.filter { $0.contains("alpha") || $0.contains("beta") }
        XCTAssertEqual(listChunks.count, 1, "got \(listChunks)")
    }

    /// An unclosed fence must not swallow the rest of the document.
    func testUnclosedFenceStillEmitsItsContent() {
        let chunks = MarkdownView.chunk("""
        # Title

        ```
        code
        more code
        """).map(\.content)

        XCTAssertTrue(chunks.contains { $0.contains("# Title") })
        XCTAssertTrue(chunks.contains { $0.contains("more code") },
                      "trailing buffer must be flushed")
    }

    func testProseIsStillSplitOnBlankLines() {
        let chunks = MarkdownView.chunk("""
        First paragraph.

        Second paragraph.
        """).map(\.content)

        XCTAssertEqual(chunks.count, 2, "ordinary paragraphs still chunk independently")
    }

    func testHeadingsRemainTheirOwnChunks() {
        let chunks = MarkdownView.chunk("""
        # Title
        body text
        """).map(\.content)

        XCTAssertEqual(chunks.first?.content(), "# Title")
    }
}

private extension String {
    func content() -> String { self }
}
