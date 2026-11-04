import XCTest
import AppKit
import SQLite
@testable import VeloxClip

/// Round-7 audit findings: five defects that the round-6 suite did not cover.
@MainActor
final class Round7RegressionTests: XCTestCase {

    // MARK: - Caps Lock breaks the Cmd+V match

    /// `.deviceIndependentFlagsMask` includes `.capsLock`, so an exact
    /// `== .command` match failed whenever Caps Lock was on — the Paste Stack
    /// stopped advancing and every paste repeated the first item.
    func testCommandOnlyIgnoresCapsLockAndFn() {
        XCTAssertTrue(NSEvent.ModifierFlags.command.isCommandOnly)
        XCTAssertTrue(NSEvent.ModifierFlags([.command, .capsLock]).isCommandOnly)
        XCTAssertTrue(NSEvent.ModifierFlags([.command, .function, .numericPad]).isCommandOnly)
    }

    func testCommandOnlyRejectsOtherChordModifiers() {
        XCTAssertFalse(NSEvent.ModifierFlags([]).isCommandOnly)
        XCTAssertFalse(NSEvent.ModifierFlags([.command, .shift]).isCommandOnly)
        XCTAssertFalse(NSEvent.ModifierFlags([.command, .option]).isCommandOnly)
        XCTAssertFalse(NSEvent.ModifierFlags([.command, .control]).isCommandOnly)
        XCTAssertFalse(NSEvent.ModifierFlags.capsLock.isCommandOnly)
    }

    // MARK: - Search selection ignored the type filter

    /// The search callback re-selected `ranked.first` from the UNFILTERED
    /// results, so with a type chip on, the selection could be a hidden row —
    /// and Enter pasted it.
    func testSearchSelectionFallsBackToTheFirstVisibleRow() {
        let text = ClipboardItem(type: "text", content: "top hit")
        let file = ClipboardItem(type: "file", content: "/tmp/report.pdf")

        let picked = SearchSelectionPolicy.selection(current: nil, ranked: [text, file], filter: .file)
        XCTAssertEqual(picked?.id, file.id)
    }

    func testSearchSelectionReplacesAHiddenCurrentRow() {
        let text = ClipboardItem(type: "text", content: "top hit")
        let file = ClipboardItem(type: "file", content: "/tmp/report.pdf")

        let picked = SearchSelectionPolicy.selection(current: text, ranked: [text, file], filter: .file)
        XCTAssertEqual(picked?.id, file.id, "a row the filter hides must not stay selected")
    }

    func testSearchSelectionKeepsAVisibleCurrentRow() {
        let first = ClipboardItem(type: "file", content: "/tmp/a")
        let second = ClipboardItem(type: "file", content: "/tmp/b")

        let picked = SearchSelectionPolicy.selection(current: second, ranked: [first, second], filter: .file)
        XCTAssertEqual(picked?.id, second.id)
    }

    func testSearchSelectionIsNilWhenNothingIsVisible() {
        let text = ClipboardItem(type: "text", content: "only text")
        XCTAssertNil(SearchSelectionPolicy.selection(current: text, ranked: [text], filter: .image))
    }

    // MARK: - Re-copying a favorite outside the window duplicated it

    /// Dedup only searched the bounded `items` window. A favorite older than
    /// the window lives only in `favoriteItems`, so copying it again inserted a
    /// second, non-favorite row with the same content.
    func testRecopyingAFavoriteOutsideTheWindowReusesIt() async throws {
        let db = DatabaseManager(databaseURL: TestSupport.makeDatabaseURL(#function))
        let settings = AppSettings(dbManager: db, autoLoad: false)
        await settings.load()
        let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: false)

        var old = ClipboardItem(type: "text", content: "an old favorite")
        old.createdAt = Date(timeIntervalSince1970: 100)
        old.isFavorite = true
        old.favoritedAt = old.createdAt
        try await db.insertClipboardItem(old)
        store.items = []
        store.favoriteItems = [old]

        store.addItem(ClipboardItem(type: "text", content: "an old favorite"))

        XCTAssertEqual(store.items.map(\.id), [old.id], "the existing favorite moves to the top, no new row")
        XCTAssertTrue(store.items.first?.isFavorite ?? false)
        XCTAssertNotNil(store.items.first?.lastUsedAt)

        let oldID = old.id
        try await TestSupport.waitUntil {
            let rows = try await db.fetchAllClipboardItems()
            return rows.first { $0.id == oldID }?.lastUsedAt != nil
        }
        let rows = try await db.fetchAllClipboardItems()
        XCTAssertEqual(rows.count, 1, "no duplicate row on disk")
        XCTAssertNotNil(rows.first?.lastUsedAt, "reuse is recorded via lastUsedAt")
    }

    // MARK: - Mosaic past the image edge was stretched and shifted

    private func colorAt(_ image: NSImage, topDown point: CGPoint) -> NSColor? {
        guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first else { return nil }
        let x = Int(point.x * CGFloat(rep.pixelsWide) / image.size.width)
        let y = Int(point.y * CGFloat(rep.pixelsHigh) / image.size.height)
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    /// The patch was built from the in-image part of the rect but drawn into
    /// the full rect, so a drag that ran off the top stretched the patch and
    /// slid it away from the pixels it was meant to cover.
    func testMosaicRunningOffTheEdgeStaysAlignedWithTheSource() throws {
        // 120x120, top 30pt black (top-down), the rest white
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 120,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let source = NSImage(size: NSSize(width: 120, height: 120))
        source.addRepresentation(rep)
        source.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 120).fill()
        NSColor.black.setFill()
        NSRect(x: 0, y: 90, width: 120, height: 30).fill()   // bottom-up y 90…120 = top-down 0…30
        source.unlockFocus()

        // Dragged from well above the image down to y = 60
        let rect = CGRect(x: 10, y: -90, width: 60, height: 150)
        let mosaic = DrawingElement(type: .mosaic, path: CGMutablePath(), color: .black, lineWidth: 1,
                                    startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY),
                                    rect: rect)

        let rendered = AnnotationRenderer.render(image: source, elements: [mosaic])

        let insideBlack = try XCTUnwrap(colorAt(rendered, topDown: CGPoint(x: 40, y: 10)))
        XCTAssertLessThan(insideBlack.redComponent, 0.5,
                          "the black band under the mosaic must stay dark, not be replaced by the stretched white half")
        let insideWhite = try XCTUnwrap(colorAt(rendered, topDown: CGPoint(x: 40, y: 50)))
        XCTAssertGreaterThan(insideWhite.redComponent, 0.5)
    }

    // MARK: - Sort indexes never matched the queries

    /// SQLite.swift compiles `??` to `ifnull(...)`, but the indexes were built
    /// on `COALESCE(...)`. SQLite matches expression indexes literally, so both
    /// list queries did a full scan plus a temp B-tree sort on every launch.
    private func plan(_ query: QueryType, at url: URL) throws -> String {
        let connection = try Connection(url.path)
        var rows: [String] = []
        let sql = query.expression
        for row in try connection.prepare("EXPLAIN QUERY PLAN " + sql.template, sql.bindings) {
            rows.append(row.compactMap { $0 as? String }.joined(separator: " "))
        }
        return rows.joined(separator: " | ")
    }

    func testHistoryOrderingAsEmittedBySQLiteSwiftUsesAnIndex() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "x"))

        // The same expression DatabaseManager.sortKey builds
        let sortKey = SQLite.Expression<Double?>("lastUsedAt") ?? SQLite.Expression<Double>("createdAt")
        let query = Table("clipboard_items").select(SQLite.Expression<String>("id")).order(sortKey.desc)
        let template = query.expression.template
        XCTAssertTrue(template.contains("ifnull"), "guard: SQLite.swift's ?? is expected to emit ifnull — got \(template)")

        let detail = try plan(query, at: url)
        XCTAssertFalse(detail.uppercased().contains("TEMP B-TREE"), "history ordering fell back to a filesort — got: \(detail)")
    }

    func testFavoritesOrderingAsEmittedBySQLiteSwiftUsesAnIndex() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        let db = DatabaseManager(databaseURL: url)
        try await db.insertClipboardItem(ClipboardItem(type: "text", content: "x"))

        // The same expression DatabaseManager.fetchFavoriteItems builds
        let favKey = SQLite.Expression<Double?>("favoritedAt") ?? SQLite.Expression<Double>("createdAt")
        let query = Table("clipboard_items")
            .select(SQLite.Expression<String>("id"))
            .filter(SQLite.Expression<Bool>("isFavorite") == true)
            .order(favKey.desc)

        let detail = try plan(query, at: url)
        XCTAssertFalse(detail.uppercased().contains("TEMP B-TREE"), "favorites ordering fell back to a filesort — got: \(detail)")
    }

    /// Databases created by earlier builds already hold the COALESCE indexes
    /// under the old names; they must be dropped rather than kept as dead weight.
    func testLegacyCoalesceIndexesAreDropped() async throws {
        let url = TestSupport.makeDatabaseURL(#function)
        // A database as an earlier build left it: real schema plus the old indexes
        _ = try await DatabaseManager(databaseURL: url).fetchAllClipboardItems()
        do {
            let legacy = try Connection(url.path)
            try legacy.run("CREATE INDEX IF NOT EXISTS idx_items_recency ON clipboard_items(COALESCE(lastUsedAt, createdAt) DESC)")
            try legacy.run("CREATE INDEX IF NOT EXISTS idx_items_fav_recency ON clipboard_items(isFavorite, COALESCE(favoritedAt, createdAt) DESC)")
        }

        // The next launch
        _ = try await DatabaseManager(databaseURL: url).fetchAllClipboardItems()

        let connection = try Connection(url.path)
        let names = try connection.prepare("SELECT name FROM sqlite_master WHERE type = 'index'")
            .compactMap { $0[0] as? String }
        XCTAssertFalse(names.contains("idx_items_recency"), "got \(names)")
        XCTAssertFalse(names.contains("idx_items_fav_recency"), "got \(names)")
    }
}
