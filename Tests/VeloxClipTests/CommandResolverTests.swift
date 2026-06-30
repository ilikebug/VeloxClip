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
}
