import XCTest
@testable import VeloxClip

@MainActor
final class AppearanceTests: XCTestCase {
    func testSystemAppearanceClearsOverride() {
        let s = AppSettings.shared
        s.appearance = "dark";   s.applyAppearance(); XCTAssertNotNil(NSApp.appearance)
        s.appearance = "light";  s.applyAppearance(); XCTAssertNotNil(NSApp.appearance)
        s.appearance = "system"; s.applyAppearance(); XCTAssertNil(NSApp.appearance)
    }
}
