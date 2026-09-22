import XCTest
import AppKit
@testable import VeloxClip

/// A mosaic is a redaction. If the block size depends on the backing scale,
/// the same region is censored more coarsely on one display than another —
/// and the editor's preview stops predicting what the export contains.
final class MosaicBlockSizeTests: XCTestCase {
    /// Builds an image of `points` logical size backed by `points * scale` pixels.
    private func image(points: CGFloat, scale: CGFloat) -> NSImage {
        let px = Int(points * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: points, height: points)
        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
        return image
    }

    /// The censored patch must represent the same amount of source detail
    /// regardless of whether the screenshot came from a 1x or a 2x display.
    func testBlockCountIsIndependentOfBackingScale() throws {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)

        let onex = try XCTUnwrap(AnnotationRenderer.pixelatedPatch(of: image(points: 300, scale: 1), forPointRect: rect))
        let twox = try XCTUnwrap(AnnotationRenderer.pixelatedPatch(of: image(points: 300, scale: 2), forPointRect: rect))

        XCTAssertEqual(onex.width, twox.width,
                       "a Retina screenshot must not end up with finer (less destroyed) mosaic blocks")
        XCTAssertEqual(onex.height, twox.height)
    }

    /// Sanity: the patch is genuinely downscaled, not passed through.
    func testPatchIsSubstantiallySmallerThanTheRegion() throws {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
        let patch = try XCTUnwrap(AnnotationRenderer.pixelatedPatch(of: image(points: 300, scale: 2), forPointRect: rect))

        XCTAssertLessThan(patch.width, 40, "300pt at factor 15 should be roughly 20 blocks across")
        XCTAssertGreaterThan(patch.width, 5)
    }

    func testTinyRegionStillProducesAtLeastOneBlock() throws {
        let rect = CGRect(x: 0, y: 0, width: 4, height: 4)
        let patch = try XCTUnwrap(AnnotationRenderer.pixelatedPatch(of: image(points: 100, scale: 2), forPointRect: rect))
        XCTAssertGreaterThanOrEqual(patch.width, 1)
        XCTAssertGreaterThanOrEqual(patch.height, 1)
    }
}
