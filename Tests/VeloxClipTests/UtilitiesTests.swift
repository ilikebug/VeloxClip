import XCTest
import AppKit
@testable import VeloxClip

final class FIFOCacheTests: XCTestCase {
    func testEvictsOldestInsertionFirst() {
        var cache = FIFOCache<String, Int>(maxEntries: 2)
        cache["a"] = 1
        cache["b"] = 2
        cache["c"] = 3

        XCTAssertNil(cache["a"], "Oldest entry should be evicted first")
        XCTAssertEqual(cache["b"], 2)
        XCTAssertEqual(cache["c"], 3)
        XCTAssertEqual(cache.count, 2)
    }

    func testOverwritingExistingKeyDoesNotEvictOrDuplicate() {
        var cache = FIFOCache<String, Int>(maxEntries: 2)
        cache["a"] = 1
        cache["b"] = 2
        cache["a"] = 10 // overwrite, no eviction

        XCTAssertEqual(cache["a"], 10)
        XCTAssertEqual(cache["b"], 2)

        // "a" keeps its original insertion position, so it is still evicted first
        cache["c"] = 3
        XCTAssertNil(cache["a"])
        XCTAssertEqual(cache["b"], 2)
        XCTAssertEqual(cache["c"], 3)
    }

    func testSettingNilRemovesEntry() {
        var cache = FIFOCache<String, Int>(maxEntries: 3)
        cache["a"] = 1
        cache["a"] = nil

        XCTAssertNil(cache["a"])
        XCTAssertEqual(cache.count, 0)

        // The freed slot is reusable without evicting anything
        cache["b"] = 2
        cache["c"] = 3
        cache["d"] = 4
        XCTAssertEqual(cache.count, 3)
    }

    func testRemoveAllResetsEvictionState() {
        var cache = FIFOCache<String, Int>(maxEntries: 2)
        cache["a"] = 1
        cache["b"] = 2
        cache.removeAll()

        XCTAssertEqual(cache.count, 0)
        cache["c"] = 3
        cache["d"] = 4
        XCTAssertEqual(cache["c"], 3)
        XCTAssertEqual(cache["d"], 4)
    }
}

final class StableHashTests: XCTestCase {
    func testDeterministicAcrossCalls() {
        XCTAssertEqual("json".stableHash, "json".stableHash)
        XCTAssertEqual("中文标签".stableHash, "中文标签".stableHash)
    }

    func testKnownValueGuardsAgainstAlgorithmChanges() {
        // Changing the algorithm silently reshuffles every user's tag colors —
        // this pinned value makes that an explicit decision
        XCTAssertEqual("json".stableHash, 3271912)
        XCTAssertEqual("".stableHash, 0)
    }

    func testAlwaysNonNegative() {
        for tag in ["a", "URL", "Code", "🎉", "很长的一个标签名称用来测试溢出行为"] {
            XCTAssertGreaterThanOrEqual(tag.stableHash, 0)
        }
    }
}

final class ThumbnailProviderTests: XCTestCase {
    func testMakeThumbnailDownscalesToMaxPixelSize() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 300,
            pixelsHigh: 150,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pngData = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        let thumbnail = try XCTUnwrap(ThumbnailProvider.makeThumbnail(from: pngData, maxPixelSize: 96))
        XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 96)
        // Aspect ratio is preserved (300×150 → 96×48)
        XCTAssertEqual(thumbnail.size.width / thumbnail.size.height, 2.0, accuracy: 0.1)
    }

    func testMakeThumbnailReturnsNilForInvalidData() {
        XCTAssertNil(ThumbnailProvider.makeThumbnail(from: Data([0x00, 0x01, 0x02, 0x03]), maxPixelSize: 96))
        XCTAssertNil(ThumbnailProvider.makeThumbnail(from: Data(), maxPixelSize: 96))
    }
}
