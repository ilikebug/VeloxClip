import XCTest
@testable import VeloxClip

@MainActor
final class AppSettingsTests: XCTestCase {
    func testLoadAppliesPersistedHistoryLimit() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        try await db.setSetting(key: "historyLimit", value: "500")

        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()

        XCTAssertEqual(settings.historyLimit, 500)
        XCTAssertTrue(settings.settingsLoaded)
    }

    func testLoadRejectsNonPositiveHistoryLimit() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        try await db.setSetting(key: "historyLimit", value: "0")

        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()

        // A stored 0/negative limit must never be applied — it would trim history to nothing
        XCTAssertEqual(settings.historyLimit, 100)
        let stored = await db.getSetting(key: "historyLimit")
        XCTAssertEqual(stored, "100")
    }

    func testChangingHistoryLimitAfterLoadPersistsAndNotifies() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()

        var notified = 0
        settings.onHistoryLimitChanged = { notified += 1 }
        settings.historyLimit = 50

        XCTAssertEqual(notified, 1)
        // didSet persists via a Task — let it run
        try await TestSupport.waitUntil { await db.getSetting(key: "historyLimit") == "50" }
        let stored = await db.getSetting(key: "historyLimit")
        XCTAssertEqual(stored, "50")
    }

    func testAppearanceRoundTripsThroughInjectedDatabase() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        try await db.setSetting(key: "appearance", value: "dark")

        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()

        XCTAssertEqual(settings.appearance, "dark")
    }
}
