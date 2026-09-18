import XCTest
@testable import VeloxClip

final class WebURLTests: XCTestCase {
    func testOnlyHTTPAndHTTPSAreOpenable() {
        XCTAssertTrue(WebURL.isOpenable("https://example.com/a?b=c"))
        XCTAssertTrue(WebURL.isOpenable("  HTTP://EXAMPLE.COM  "))
        XCTAssertFalse(WebURL.isOpenable("file:///Users/me/payload.command"))
        XCTAssertFalse(WebURL.isOpenable("javascript:alert(1)"))
        XCTAssertFalse(WebURL.isOpenable("mailto:a@b.co"))
        XCTAssertFalse(WebURL.isOpenable("not a url"))
        XCTAssertFalse(WebURL.isOpenable(nil))
    }

    func testOpenableURLObjectCheck() {
        XCTAssertTrue(WebURL.isOpenable(URL(string: "https://example.com")!))
        XCTAssertFalse(WebURL.isOpenable(URL(string: "file:///tmp/x")!))
    }
}
