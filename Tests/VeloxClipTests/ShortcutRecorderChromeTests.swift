import XCTest
@testable import VeloxClip

final class ShortcutRecorderChromeTests: XCTestCase {
    func testLightAppearanceUsesVisibleDarkChrome() {
        let chrome = ShortcutRecorderChrome(isDark: false)

        XCTAssertEqual(chrome.backgroundWhite, 0.0)
        XCTAssertEqual(chrome.backgroundAlpha, 0.045)
        XCTAssertEqual(chrome.borderWhite, 0.0)
        XCTAssertEqual(chrome.borderAlpha, 0.14)
    }

    func testDarkAppearanceUsesLightChrome() {
        let chrome = ShortcutRecorderChrome(isDark: true)

        XCTAssertEqual(chrome.backgroundWhite, 1.0)
        XCTAssertEqual(chrome.backgroundAlpha, 0.08)
        XCTAssertEqual(chrome.borderWhite, 1.0)
        XCTAssertEqual(chrome.borderAlpha, 0.14)
    }
}
