import XCTest
@testable import VeloxClip

final class MainSearchBarLayoutTests: XCTestCase {
    func testSearchBarUsesTallerLayout() {
        XCTAssertEqual(MainSearchBarLayout.fontSize, 14)
        XCTAssertEqual(MainSearchBarLayout.verticalPadding, 14)
    }
}
