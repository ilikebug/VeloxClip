import XCTest
@testable import VeloxClip

/// Covers the logic pulled out of preview `body`s so it could run off the main
/// thread. Each of these used to be a computed property or an `.onAppear` call
/// re-running on every body evaluation.
final class PreviewComputationTests: XCTestCase {

    // MARK: - Text statistics

    func testStatsCountWordsCharactersLinesAndParagraphs() {
        let text = "first para line one\nline two\n\nsecond para"
        let stats = TextSummaryPresentation.stats(for: text)

        XCTAssertEqual(stats.words, 8)
        XCTAssertEqual(stats.characters, text.count)
        XCTAssertEqual(stats.lines, 4)
        XCTAssertEqual(stats.paragraphs, 2)
    }

    func testEmptyTextHasZeroCounts() {
        let stats = TextSummaryPresentation.stats(for: "")
        XCTAssertEqual(stats.words, 0)
        XCTAssertEqual(stats.characters, 0)
        XCTAssertEqual(stats.paragraphs, 0)
    }

    func testBlankParagraphsAreNotCounted() {
        // Runs of blank lines must not inflate the paragraph count
        let text = "one\n\n\n\n   \n\ntwo"
        XCTAssertEqual(TextSummaryPresentation.paragraphs(in: text), ["one", "two"])
    }

    // MARK: - Language detection

    func testDetectsLanguagesByKeyword() {
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "func greet() { let x = 1 }"), "Swift")
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "def main():\n    import os"), "Python")
    }

    func testFallsBackToStructuralRulesWhenNoKeywordMatches() {
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "{\"a\": 1}"), "JSON")
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "<!doctype html><p>x</p>"), "HTML")
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "body { color: red }"), "CSS")
    }

    func testPlainProseIsNotMistakenForCode() {
        XCTAssertEqual(CodePreviewView.detectLanguage(in: "just some notes to myself"), "Plain Text")
    }

    // MARK: - QR generation

    func testQRCodeIsGeneratedAtTheRequestedSize() {
        let image = URLPreviewView.qrImage(from: "https://example.com", size: 148)
        XCTAssertNotNil(image)
        // Core Image rounds to whole pixels; allow a point of slack
        XCTAssertEqual(image?.size.width ?? 0, 148, accuracy: 1.5)
    }

    func testQRGenerationIsDeterministic() {
        // It's a pure function of the URL, which is why caching it is safe
        let first = URLPreviewView.qrImage(from: "https://example.com", size: 64)
        let second = URLPreviewView.qrImage(from: "https://example.com", size: 64)
        XCTAssertEqual(first?.size, second?.size)
    }

    // MARK: - File entries

    func testReadEntriesReportsExistenceAndSize() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VeloxClipFiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let real = dir.appendingPathComponent("real.txt")
        try Data("hello".utf8).write(to: real)
        let missing = dir.appendingPathComponent("gone.txt").path

        let entries = MultiFilePreview.readEntries([real.path, missing, dir.path])

        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].exists)
        XCTAssertEqual(entries[0].size, 5)
        XCTAssertEqual(entries[0].name, "real.txt")
        XCTAssertFalse(entries[1].exists, "a deleted path must be reported, not crash")
        XCTAssertTrue(entries[2].isDirectory)
    }

    func testReadFileInfoHandlesAMissingPath() {
        let info = SingleFilePreview.readFileInfo(at: "/nonexistent-\(UUID().uuidString)")
        XCTAssertFalse(info.exists)
        XCTAssertEqual(info.size, 0)
    }
}
