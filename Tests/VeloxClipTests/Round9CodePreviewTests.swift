import XCTest
import SwiftUI
@testable import VeloxClip

/// Round-9 low-priority findings in the code preview: language detection,
/// line splitting, the highlight regex table and the Format action.
@MainActor
final class Round9CodePreviewTests: XCTestCase {

    // MARK: - JavaScript/TypeScript ties were won at random

    /// Every JavaScript keyword is also a TypeScript keyword, so plain JS
    /// scores a tie. The winner was whichever Dictionary iteration reached
    /// first, which is reseeded on every launch.
    func testTiedLanguagesResolveTheSameWayEveryLaunch() {
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "const x = await fetch(url)"), "JavaScript")
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "export const f = async () => await g()"), "JavaScript")
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "let a = 1; const b = 2; export default a"), "JavaScript")
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "export const sum = (a, b) => a + b"), "JavaScript")
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "#include <stdio.h>"), "C")
    }

    // MARK: - CRLF showed a blank line between every line

    func testCRLFIsOneLineBreak() {
        XCTAssertEqual(CodePreviewView.codeLines(for: "a\r\nb\r\nc"), ["a", "b", "c"])
        XCTAssertEqual(CodePreviewView.codeLines(for: "a\r\n\r\nb"), ["a", "", "b"])
        XCTAssertEqual(CodePreviewView.codeLines(for: "a\rb\nc"), ["a", "b", "c"])
        XCTAssertEqual(CodePreviewView.formatted("if x {\r\ny\r\n}"), "if x {\n    y\n}")
    }

    // MARK: - Highlight regexes that never matched or matched too much

    /// Colours of the runs covering the first occurrence of `token`.
    private func colors(of token: String, in line: String, language: String) -> [Color?] {
        let attr = CodePreviewView.highlightSyntax(line: line, language: language, fontSize: 13)
        guard let range = attr.range(of: token) else {
            XCTFail("\(token) not in \(line)")
            return []
        }
        return attr[range].runs.map(\.foregroundColor)
    }

    /// `\b` needs a word character next to it, so keywords starting with
    /// `#`, `<` or `@` never matched; `#.*` then greyed the C directive out
    /// as a comment.
    func testKeywordsStartingWithPunctuationAreHighlighted() {
        XCTAssertEqual(colors(of: "#include", in: "#include <stdio.h>", language: "C"), [.blue])
        XCTAssertEqual(colors(of: "<stdio.h>", in: "#include <stdio.h>", language: "C"), [nil])
        XCTAssertEqual(colors(of: "<html", in: "<html lang=en>", language: "HTML"), [.blue])
        XCTAssertEqual(colors(of: "@media", in: "@media screen {", language: "CSS"), [.blue])
    }

    /// SQL is detected case-insensitively but was only highlighted in capitals.
    func testLowercaseSQLKeywordsAreHighlighted() {
        XCTAssertEqual(colors(of: "select", in: "select * from users", language: "SQL"), [.blue])
        XCTAssertEqual(colors(of: "from", in: "select * from users", language: "SQL"), [.blue])
    }

    /// `//.*` matched inside a string literal and greyed out the rest of the line.
    func testCommentMarkerInsideAStringIsNotAComment() {
        let line = #"let url = "https://x.com"; let n = 1"#
        XCTAssertEqual(colors(of: #""https://x.com""#, in: line, language: "Swift"), [.green])
        XCTAssertEqual(colors(of: "let n", in: line, language: "Swift"), [.blue, nil])
        XCTAssertEqual(colors(of: ##""#fff""##, in: ##"c = "#fff""##, language: "Python"), [.green])
        // Real comments are still comments
        XCTAssertEqual(colors(of: "// note", in: "let a = 1 // note", language: "Swift"), [.gray])
        XCTAssertEqual(colors(of: "# note", in: "a = 1 # note", language: "Python"), [.gray])
    }

    /// The greedy match that started inside the string had already consumed
    /// the real comment after it.
    func testCommentAfterAStringWithAMarkerIsStillAComment() {
        let swift = #"let u = "https://x.com" // link"#
        XCTAssertEqual(colors(of: "// link", in: swift, language: "Swift"), [.gray])
        XCTAssertEqual(colors(of: #""https://x.com""#, in: swift, language: "Swift"), [.green])
        XCTAssertEqual(colors(of: "# colour", in: ##"c = "#fff"  # colour"##, language: "Python"), [.gray])
    }

    /// `#` only starts a comment in Python, Shell and YAML; `//` is integer
    /// division in Python and an unquoted URL in a shell command.
    func testCommentSyntaxFollowsTheLanguage() {
        XCTAssertEqual(colors(of: "DEBUG", in: "#if DEBUG", language: "Swift"), [nil])
        XCTAssertEqual(colors(of: "// b", in: "x = a // b", language: "Python"), [nil])
        XCTAssertEqual(colors(of: "//x.com", in: "curl https://x.com", language: "Shell"), [nil])
    }

    /// `"[^"]*"` stopped at an escaped quote.
    func testEscapedQuotesStayInsideTheString() {
        let literal = #""say \"hi\" now""#
        XCTAssertEqual(colors(of: literal, in: "let s = \(literal)", language: "Swift"), [.green])
    }

    // MARK: - Format drifted on `} else {`

    func testFormatDoesNotDriftOnCloseAndOpenOnOneLine() {
        let source = "if a {\nx\n} else if b {\ny\n} else {\nz\n}\ndone()"
        let expected = "if a {\n    x\n} else if b {\n    y\n} else {\n    z\n}\ndone()"
        XCTAssertEqual(CodePreviewView.formatted(source), expected)

        // A block opened and closed on one line changes nothing; `},` closes one
        let other = "f {\ng { h }\nitems = [\n{\nid\n},\n]\n}"
        let otherExpected = "f {\n    g { h }\n    items = [\n        {\n            id\n        },\n    ]\n}"
        XCTAssertEqual(CodePreviewView.formatted(other), otherExpected)
    }
}
