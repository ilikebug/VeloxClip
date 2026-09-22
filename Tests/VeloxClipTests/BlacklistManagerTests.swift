import XCTest
@testable import VeloxClip

/// The blacklist decides which apps' copies never reach history. It shipped as
/// four hardcoded bundle IDs with no UI, so users of any other password manager
/// (Bitwarden, Enpass, KeePassXC…) had their secrets recorded.
@MainActor
final class BlacklistManagerTests: XCTestCase {
    private func makeManager() -> BlacklistManager {
        BlacklistManager(userAdded: [], userRemoved: [])
    }

    func testBundledPasswordManagersAreIgnoredByDefault() {
        let manager = makeManager()
        XCTAssertTrue(manager.shouldIgnore(bundleID: "com.1password.1password"))
        XCTAssertTrue(manager.shouldIgnore(bundleID: "com.apple.keychainaccess"))
        XCTAssertFalse(manager.shouldIgnore(bundleID: "com.apple.Safari"))
    }

    func testNilBundleIDIsNeverIgnored() {
        XCTAssertFalse(makeManager().shouldIgnore(bundleID: nil))
    }

    /// The gap this closes: any other password manager.
    func testUserAddedAppIsIgnored() {
        let manager = BlacklistManager(userAdded: ["com.bitwarden.desktop"], userRemoved: [])
        XCTAssertTrue(manager.shouldIgnore(bundleID: "com.bitwarden.desktop"))
    }

    func testUserCanRemoveABundledDefault() {
        let manager = BlacklistManager(userAdded: [], userRemoved: ["com.apple.keychainaccess"])
        XCTAssertFalse(manager.shouldIgnore(bundleID: "com.apple.keychainaccess"),
                       "a default the user removed must stay removed")
        XCTAssertTrue(manager.shouldIgnore(bundleID: "com.1password.1password"),
                      "…without affecting the others")
    }

    /// Bundle IDs are case-insensitive on macOS; the blacklist must not be
    /// bypassed by case.
    func testMatchingIsCaseInsensitive() {
        let manager = BlacklistManager(userAdded: ["com.Example.Vault"], userRemoved: [])
        XCTAssertTrue(manager.shouldIgnore(bundleID: "com.example.vault"))
        XCTAssertTrue(manager.shouldIgnore(bundleID: "COM.EXAMPLE.VAULT"))
        XCTAssertTrue(manager.shouldIgnore(bundleID: "COM.1PASSWORD.1PASSWORD"))
    }

    /// Removing wins over adding, so a single list can express both.
    func testRemovalTakesPrecedenceOverAddition() {
        let manager = BlacklistManager(userAdded: ["com.foo.bar"], userRemoved: ["com.foo.bar"])
        XCTAssertFalse(manager.shouldIgnore(bundleID: "com.foo.bar"))
    }

    func testBlockedListIsTheEffectiveSetSortedForDisplay() {
        let manager = BlacklistManager(userAdded: ["com.aaa.app"], userRemoved: ["com.apple.keychainaccess"])
        let blocked = manager.blockedBundleIDs

        XCTAssertTrue(blocked.contains("com.aaa.app"))
        XCTAssertFalse(blocked.contains("com.apple.keychainaccess"))
        XCTAssertEqual(blocked, blocked.sorted(), "shown in a stable order")
    }

    // MARK: - Persistence round-trip

    func testUserEditsSurviveAReload() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        // Writes are suppressed until load() finishes, so a fresh install can't
        // persist its own defaults over stored values.
        await settings.load()

        settings.blacklistUserAdded = ["com.bitwarden.desktop"]
        settings.blacklistUserRemoved = ["com.apple.Passwords"]

        try await TestSupport.waitUntil {
            let raw = await db.getSetting(key: "blacklistUserAdded")
            return raw?.contains("bitwarden") == true
        }

        let reloaded = AppSettings(dbManager: db, autoLoad: false)
        await reloaded.load()

        XCTAssertEqual(reloaded.blacklistUserAdded, ["com.bitwarden.desktop"])
        XCTAssertEqual(reloaded.blacklistUserRemoved, ["com.apple.Passwords"])
    }
}
