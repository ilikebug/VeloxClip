import XCTest
@testable import VeloxClip

final class OverlayWindowLayoutTests: XCTestCase {
    func testOverlayWindowUsesSixRowHeight() {
        XCTAssertEqual(OverlayWindowLayout.width, 560)
        XCTAssertEqual(OverlayWindowLayout.height, 520)
    }
}
