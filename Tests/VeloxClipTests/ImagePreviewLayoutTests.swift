import SwiftUI
import XCTest
@testable import VeloxClip

final class ImagePreviewLayoutTests: XCTestCase {
    func testDetailImagePreviewFitsPanelWithoutHorizontalScrolling() {
        let policy = ImagePreviewLayoutPolicy.detailImage

        XCTAssertEqual(policy.scrollAxes, .vertical)
        XCTAssertEqual(policy.defaultZoomLevel, 1.0)
        XCTAssertEqual(policy.maximumZoomLevel, 1.0)
        XCTAssertTrue(policy.fitsImageToAvailablePanel)
    }
}
