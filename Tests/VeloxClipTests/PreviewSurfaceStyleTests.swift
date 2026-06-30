import XCTest
@testable import VeloxClip

final class PreviewSurfaceStyleTests: XCTestCase {
    func testDetailPreviewSurfaceUsesOpaqueWindowBackground() {
        XCTAssertTrue(PreviewSurfaceStyle.usesOpaqueWindowBackground)
    }
}
