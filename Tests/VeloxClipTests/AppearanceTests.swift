import XCTest
@testable import VeloxClip

@MainActor
final class AppearanceTests: XCTestCase {
    func testSystemAppearanceClearsOverride() async {
        // Injected DB so the test never writes the developer's real settings
        let s = AppSettings(dbManager: DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function)), autoLoad: false)
        await s.load()
        s.appearance = "dark";   s.applyAppearance(); XCTAssertNotNil(NSApp.appearance)
        s.appearance = "light";  s.applyAppearance(); XCTAssertNotNil(NSApp.appearance)
        s.appearance = "system"; s.applyAppearance(); XCTAssertNil(NSApp.appearance)
    }
}
