import XCTest
import Combine
@testable import VeloxClip

final class LocalizationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    func testAppLanguageDisplayNamesAreLocalized() {
        XCTAssertEqual(AppLanguage.system.displayName(language: .en), "Follow System")
        XCTAssertEqual(AppLanguage.zhHans.displayName(language: .en), "Simplified Chinese")
        XCTAssertEqual(AppLanguage.en.displayName(language: .zhHans), "English")
    }

    func testLocalizationReturnsEnglishAndChineseStrings() {
        XCTAssertEqual(L10n.string("settings.language", language: .en), "Language")
        XCTAssertEqual(L10n.string("settings.language", language: .zhHans), "语言")
    }

    func testLanguageResourceNamesMatchSwiftPMOutput() {
        XCTAssertEqual(AppLanguage.en.resourceName, "en")
        XCTAssertEqual(AppLanguage.zhHans.resourceName, "zh-hans")
    }

    func testLocalizationFormatsCountedStrings() {
        XCTAssertEqual(L10n.format("common.items.count", 3, language: .en), "3 items")
        XCTAssertEqual(L10n.format("common.items.count", 3, language: .zhHans), "3 项")
    }

    func testCurrentLanguageLookupIsSafeOffMainActor() async {
        L10n.updateCurrentLanguage(.en)

        let value = await Task.detached {
            L10n.string("settings.language")
        }.value

        XCTAssertEqual(value, "Language")
        L10n.updateCurrentLanguage(.system)
    }

    @MainActor
    func testSettingsLanguageCacheUpdatesBeforeObjectWillChange() {
        let settings = AppSettings.shared
        let originalLanguage = settings.appLanguage
        defer {
            settings.appLanguage = originalLanguage
            L10n.updateCurrentLanguage(originalLanguage)
        }

        settings.appLanguage = .en
        var languageObservedDuringChange: String?
        settings.objectWillChange
            .sink {
                languageObservedDuringChange = L10n.string("settings.language")
            }
            .store(in: &cancellables)

        settings.appLanguage = .zhHans

        XCTAssertEqual(languageObservedDuringChange, "语言")
    }
}
