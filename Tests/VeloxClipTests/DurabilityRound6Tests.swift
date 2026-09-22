import XCTest
@testable import VeloxClip

/// Round-6 durability findings: silent data loss and failures the user never
/// sees.
@MainActor
final class DurabilityRound6Tests: XCTestCase {

    private func makeStore(limit: Int = 100) async throws -> (ClipboardStore, DatabaseManager, AppSettings) {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        settings.historyLimit = limit
        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: false)
        return (store, db, settings)
    }

    // MARK: - NUL truncation (critical: silent, unrecoverable data loss)

    /// SQLite binds text with C-string semantics, so a clip containing U+0000
    /// is truncated at the NUL on write. The UI keeps showing the whole clip
    /// until relaunch, when everything past the NUL is gone.
    func testTextContainingNulSurvivesARoundTrip() async throws {
        let (_, db, _) = try await makeStore()
        let original = "BEGIN\0SECRET-TAIL-THAT-MUST-SURVIVE"
        let item = ClipboardItem(type: "text", content: original)
        try await db.insertClipboardItem(item)

        let readBack = try await db.fetchAllClipboardItems().first { $0.id == item.id }?.content
        XCTAssertEqual(
            readBack?.count, ClipboardItem.sanitizedContent(original)?.count,
            "content was truncated at the NUL: stored \(readBack?.count ?? -1) of \(original.count) chars"
        )
        XCTAssertTrue(
            readBack?.contains("SECRET-TAIL") ?? false,
            "everything past the NUL was silently lost; got \(readBack ?? "nil")"
        )
    }

    /// Two clips that differ only after a NUL must not collapse into one row —
    /// otherwise dedup merges them and the user pastes the wrong clip.
    func testTwoClipsDifferingAfterANulStayDistinct() async throws {
        let (_, db, _) = try await makeStore()
        let alpha = ClipboardItem(type: "text", content: "prefix\0ALPHA")
        let bravo = ClipboardItem(type: "text", content: "prefix\0BRAVO")
        try await db.insertClipboardItem(alpha)
        try await db.insertClipboardItem(bravo)

        let stored = try await db.fetchAllClipboardItems().compactMap(\.content)
        XCTAssertEqual(Set(stored).count, 2, "two distinct clips collapsed into one stored row: \(stored)")
    }

    /// Ingestion must sanitize, so what reaches the store is already safe.
    func testIngestionSanitizesNulBytes() {
        let kind = IngestionPipeline.classify(PasteboardPayload(text: "token=AKIA123\0rest-of-file"))
        guard case .text(let stored) = kind else {
            return XCTFail("a clip with a NUL must still be ingested, got \(kind)")
        }
        XCTAssertFalse(stored.contains("\0"), "the NUL reached the store and will truncate the row")
        XCTAssertTrue(stored.contains("rest-of-file"), "the tail must survive sanitizing; got \(stored)")
    }

    // MARK: - Failures the UI reports as success

    /// `enforceHistoryLimit` removed rows from the UI and fired the delete with
    /// `try?`. When the delete fails the rows stay on disk and come back on the
    /// next launch — a privacy failure for the feature meant to purge clips.
    func testHistoryTrimReportsAFailedDeleteInsteadOfLosingIt() async throws {
        let (store, db, settings) = try await makeStore(limit: 2)
        for i in 0..<5 {
            await store.addItem(ClipboardItem(type: "text", content: "secret \(i)"))
        }
        try await TestSupport.waitUntil { try await db.fetchAllClipboardItems().count == 5 }

        // Make every future write fail.
        await db.closeForTesting()
        let path = await db.databaseURL.path
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        ErrorHandler.shared.currentError = nil
        settings.historyLimit = 2
        await store.enforceHistoryLimitOnDisk()
        try? await Task.sleep(for: .milliseconds(400))

        let onDisk = (try? await db.fetchAllClipboardItems().count) ?? -1
        if onDisk > store.items.count {
            XCTAssertNotNil(
                ErrorHandler.shared.currentError,
                "\(onDisk - store.items.count) rows the user watched leave the list are still stored, with no error shown"
            )
        }
    }

    /// Settings writes were all `try?`: the UI applied the change, the write
    /// failed, and the next launch silently reverted every choice.
    func testFailedSettingsWriteIsReported() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()

        await db.closeForTesting()
        let path = await db.databaseURL.path
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        ErrorHandler.shared.currentError = nil
        settings.historyLimit = 5000
        try? await Task.sleep(for: .milliseconds(400))

        let stored = try? await db.getSetting(key: "historyLimit")
        if stored != "5000" {
            XCTAssertNotNil(
                ErrorHandler.shared.currentError,
                "a settings change that did not persist must be reported, not swallowed"
            )
        }
    }

    // MARK: - Errors the user cannot see

    /// `ErrorHandler` cleared itself after 5 seconds, and its only renderer is
    /// the overlay window — which a menu bar app keeps hidden. Every carefully
    /// built rollback-and-report path was unreachable in normal use.
    func testAnErrorRaisedWhileHiddenIsStillThereWhenTheWindowOpens() async {
        ErrorHandler.shared.currentError = nil
        ErrorHandler.shared.handle(DatabaseError.connectionFailed)
        XCTAssertNotNil(ErrorHandler.shared.currentError)

        try? await Task.sleep(for: .seconds(6))

        XCTAssertNotNil(
            ErrorHandler.shared.currentError,
            "the error self-destructed before the user could open the window"
        )
        ErrorHandler.shared.dismiss()
        XCTAssertNil(ErrorHandler.shared.currentError, "dismissing must clear it")
    }

    /// Three unrecoverable states must not share one meaningless message.
    func testDatabaseErrorsExplainThemselves() {
        let cases: [DatabaseError] = [
            .schemaTooNew(found: 99, supported: 1),
            .connectionFailed,
        ]
        for error in cases {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty, "\(error) has no errorDescription")
            XCTAssertFalse(
                message.contains("couldn’t be completed"),
                "\(error) falls back to the generic Foundation string: \(message)"
            )
        }
        let schema = DatabaseError.schemaTooNew(found: 99, supported: 1).errorDescription ?? ""
        XCTAssertTrue(schema.contains("99"), "the refusal must name the version it found; got \(schema)")
    }
}
