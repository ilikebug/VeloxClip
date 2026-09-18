import Foundation
import AppKit

enum TestSupport {
    /// A fresh temp-directory SQLite path per test so nothing touches the real Application Support DB.
    static func makeDatabaseURL(_ name: String) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root.appendingPathComponent("VeloxClipTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("veloxclip.db")
    }

    /// Polls `condition` (up to ~1s) for work a fire-and-forget Task persists asynchronously.
    static func waitUntil(_ condition: @Sendable () async throws -> Bool) async throws {
        for _ in 0..<100 {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// A tiny valid PNG blob for image-item tests.
    static func makePNG(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }
}
