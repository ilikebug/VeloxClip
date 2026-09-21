import XCTest
@testable import VeloxClip

final class CommandResolverTests: XCTestCase {
    func testColorItemHasHexAndRgbCommands() {
        let ids = CommandResolver.commands(forType: "color").map(\.kind.rawValue)
        XCTAssertTrue(ids.contains("paste"))
        XCTAssertTrue(ids.contains("copyHex"))
        XCTAssertTrue(ids.contains("copyRgb"))
    }
    func testTextItemHasNoColorCommands() {
        let ids = CommandResolver.commands(forType: "text").map(\.kind.rawValue)
        XCTAssertTrue(ids.contains("paste"))
        XCTAssertFalse(ids.contains("copyHex"))
        XCTAssertFalse(ids.contains("copyRgb"))
    }
    func testAllTypesHaveCoreCommands() {
        for t in ["text", "image", "file", "rtf"] {
            let ids = Set(CommandResolver.commands(forType: t).map(\.kind.rawValue))
            XCTAssertEqual(Set(["paste","copy","favorite","stack","delete"]).subtracting(ids), [])
        }
    }

    func testMainActionKeyHintsMatchCurrentRouting() {
        let commands = Dictionary(uniqueKeysWithValues: CommandResolver.commands(forType: "text").map { ($0.kind, $0) })
        XCTAssertEqual(commands[.detail]?.keyHint, "⌘→")
        XCTAssertEqual(commands[.stack]?.keyHint, "⌘⏎")
    }

    func testImageItemHasEditImageCommand() {
        let item = ClipboardItem(type: "image", data: Data([0x89]))
        let ids = CommandResolver.commands(for: item).map(\.kind.rawValue)

        XCTAssertTrue(ids.contains("editImage"))
    }

    func testURLTextItemHasOpenURLCommand() {
        let item = ClipboardItem(type: "text", content: "https://example.com", sourceApp: nil)
        let ids = CommandResolver.commands(for: item).map(\.kind.rawValue)

        XCTAssertTrue(ids.contains("openURL"))
    }

    func testURLTagWithoutOpenableContentDoesNotShowOpenURLCommand() {
        var item = ClipboardItem(type: "text", content: "not a link", sourceApp: nil)
        item.tags = ["URL"]
        let ids = CommandResolver.commands(for: item).map(\.kind.rawValue)

        XCTAssertFalse(ids.contains("openURL"))
    }

    func testNonWebSchemesNeverGetOpenURLCommand() {
        for content in ["file:///etc/passwd", "mailto:a@b.co", "javascript:alert(1)", "ftp://example.com"] {
            let item = ClipboardItem(type: "text", content: content, sourceApp: nil)
            XCTAssertFalse(CommandResolver.commands(for: item).map(\.kind.rawValue).contains("openURL"), content)
        }
    }

    func testDetailCommandIsHiddenWhileDetailIsPresented() {
        let item = ClipboardItem(type: "text", content: "x", sourceApp: nil)
        let ids = CommandResolver.commands(for: item, isDetailPresented: true).map(\.kind.rawValue)
        XCTAssertFalse(ids.contains("detail"))
        XCTAssertTrue(ids.contains("paste"))
    }

    func testFileItemHasRevealAndCopyPathCommands() {
        let item = ClipboardItem(type: "file", content: "/tmp/a.txt", sourceApp: nil)
        let ids = CommandResolver.commands(for: item).map(\.kind.rawValue)

        XCTAssertTrue(ids.contains("revealInFinder"))
        XCTAssertTrue(ids.contains("copyPath"))
    }

    func testFileItemWithoutPathsDoesNotShowFileCommands() {
        let item = ClipboardItem(type: "file", content: nil, sourceApp: nil)
        let ids = CommandResolver.commands(for: item).map(\.kind.rawValue)

        XCTAssertFalse(ids.contains("revealInFinder"))
        XCTAssertFalse(ids.contains("copyPath"))
    }
}
