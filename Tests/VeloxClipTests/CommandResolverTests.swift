import XCTest
@testable import VeloxClip

final class CommandResolverTests: XCTestCase {
    func testColorItemHasHexAndRgbCommands() {
        let ids = CommandResolver.commands(forType: "color").map(\.id)
        XCTAssertTrue(ids.contains("paste"))
        XCTAssertTrue(ids.contains("copyHex"))
        XCTAssertTrue(ids.contains("copyRgb"))
    }
    func testTextItemHasNoColorCommands() {
        let ids = CommandResolver.commands(forType: "text").map(\.id)
        XCTAssertTrue(ids.contains("paste"))
        XCTAssertFalse(ids.contains("copyHex"))
        XCTAssertFalse(ids.contains("copyRgb"))
    }
    func testAllTypesHaveCoreCommands() {
        for t in ["text", "image", "file", "rtf"] {
            let ids = Set(CommandResolver.commands(forType: t).map(\.id))
            XCTAssertEqual(Set(["paste","copy","favorite","stack","delete"]).subtracting(ids), [])
        }
    }

    func testMainActionKeyHintsMatchCurrentRouting() {
        let commands = Dictionary(uniqueKeysWithValues: CommandResolver.commands(forType: "text").map { ($0.id, $0) })
        XCTAssertEqual(commands["detail"]?.keyHint, "⌘→")
        XCTAssertEqual(commands["stack"]?.keyHint, "⌘⏎")
    }

    func testImageItemHasEditImageCommand() {
        let item = ClipboardItem(type: "image", data: Data([0x89]))
        let ids = CommandResolver.commands(for: item).map(\.id)

        XCTAssertTrue(ids.contains("editImage"))
    }

    func testURLTextItemHasOpenURLCommand() {
        let item = ClipboardItem(type: "text", content: "https://example.com", sourceApp: nil)
        let ids = CommandResolver.commands(for: item).map(\.id)

        XCTAssertTrue(ids.contains("openURL"))
    }

    func testURLTagWithoutOpenableContentDoesNotShowOpenURLCommand() {
        var item = ClipboardItem(type: "text", content: "not a link", sourceApp: nil)
        item.tags = ["URL"]
        let ids = CommandResolver.commands(for: item).map(\.id)

        XCTAssertFalse(ids.contains("openURL"))
    }

    func testFileItemHasRevealAndCopyPathCommands() {
        let item = ClipboardItem(type: "file", content: "/tmp/a.txt", sourceApp: nil)
        let ids = CommandResolver.commands(for: item).map(\.id)

        XCTAssertTrue(ids.contains("revealInFinder"))
        XCTAssertTrue(ids.contains("copyPath"))
    }

    func testFileItemWithoutPathsDoesNotShowFileCommands() {
        let item = ClipboardItem(type: "file", content: nil, sourceApp: nil)
        let ids = CommandResolver.commands(for: item).map(\.id)

        XCTAssertFalse(ids.contains("revealInFinder"))
        XCTAssertFalse(ids.contains("copyPath"))
    }
}
