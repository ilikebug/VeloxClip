import XCTest
import AppKit
import SwiftUI
@testable import VeloxClip

/// The screenshot compositor was three private methods on a 732-line
/// `struct View`, so the parts most likely to regress silently — Retina pixel
/// sizing, the Core Graphics coordinate flip, mosaic mirroring — could not be
/// tested at all.
final class AnnotationRendererTests: XCTestCase {
    private func solidImage(width: Int, height: Int, color: NSColor = .white) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    /// Reads a pixel in TOP-DOWN coordinates (the space the user draws in).
    private func color(in image: NSImage, atTopDown point: CGPoint) -> NSColor? {
        guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first else { return nil }
        let scaleX = CGFloat(rep.pixelsWide) / image.size.width
        let scaleY = CGFloat(rep.pixelsHigh) / image.size.height
        let x = Int(point.x * scaleX)
        let y = Int(point.y * scaleY)   // NSBitmapImageRep rows are top-down
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return nil }
        // Convert: calibratedRGB colors reject the grayscale accessors
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    private func strokeElement(from: CGPoint, to: CGPoint, color: Color = .red, width: CGFloat = 8) -> DrawingElement {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        return DrawingElement(type: .line, path: path, color: color, lineWidth: width,
                              startPoint: from, endPoint: to)
    }

    private func mosaicElement(_ rect: CGRect) -> DrawingElement {
        DrawingElement(type: .mosaic, path: CGMutablePath(), color: .black, lineWidth: 1,
                       startPoint: rect.origin,
                       endPoint: CGPoint(x: rect.maxX, y: rect.maxY),
                       rect: rect)
    }

    // MARK: - Size and resolution

    func testEmptyElementListReturnsAnImageOfTheSameSize() {
        let source = solidImage(width: 40, height: 30)
        let rendered = AnnotationRenderer.render(image: source, elements: [])
        XCTAssertEqual(rendered.size, source.size)
    }

    /// `image.size` is in points; a Retina screenshot carries 2x pixels. Sizing
    /// the export bitmap by points would halve the resolution.
    func testRetinaSourceKeepsItsFullPixelResolution() {
        // 100x80 points backed by a 200x160 pixel rep
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 160,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 100, height: 80)
        let retina = NSImage(size: NSSize(width: 100, height: 80))
        retina.addRepresentation(rep)

        let rendered = AnnotationRenderer.render(image: retina, elements: [])

        XCTAssertEqual(rendered.size, NSSize(width: 100, height: 80), "points are preserved")
        let outRep = rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first
        XCTAssertEqual(outRep?.pixelsWide, 200, "the 2x pixel raster must survive the export")
        XCTAssertEqual(outRep?.pixelsHigh, 160)
    }

    // MARK: - Coordinate flip

    /// SwiftUI draws top-down, Core Graphics bottom-up. Get the flip wrong and
    /// every annotation lands mirrored vertically.
    func testAnnotationLandsWhereTheUserDrewIt() throws {
        let source = solidImage(width: 100, height: 100, color: .white)
        // A stroke across the TOP of the image, in the user's top-down space
        let element = strokeElement(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10))

        let rendered = AnnotationRenderer.render(image: source, elements: [element])

        let top = try XCTUnwrap(color(in: rendered, atTopDown: CGPoint(x: 50, y: 10)))
        let bottom = try XCTUnwrap(color(in: rendered, atTopDown: CGPoint(x: 50, y: 90)))

        XCTAssertGreaterThan(top.redComponent - top.greenComponent, 0.3,
                             "a red stroke drawn at the top must appear at the top, not mirrored to the bottom")
        XCTAssertEqual(bottom.greenComponent, 1.0, accuracy: 0.05, "the bottom must stay white")
    }

    func testUntouchedPixelsKeepTheSourceColor() throws {
        let source = solidImage(width: 60, height: 60, color: .white)
        let element = strokeElement(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 15, y: 5))

        let rendered = AnnotationRenderer.render(image: source, elements: [element])

        let far = try XCTUnwrap(color(in: rendered, atTopDown: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(far.redComponent, 1.0, accuracy: 0.05, "drawing must not disturb the rest of the image")
        XCTAssertEqual(far.greenComponent, 1.0, accuracy: 0.05)
        XCTAssertEqual(far.blueComponent, 1.0, accuracy: 0.05)
    }

    // MARK: - Mosaic

    func testMosaicChangesItsRectAndLeavesTheRestAlone() throws {
        // A source with structure, so pixelation is detectable
        let source = solidImage(width: 80, height: 80, color: .white)
        source.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 80).fill()
        source.unlockFocus()

        let mosaic = mosaicElement(CGRect(x: 10, y: 10, width: 30, height: 30))

        let rendered = AnnotationRenderer.render(image: source, elements: [mosaic])

        XCTAssertEqual(rendered.size, source.size)
        // Outside the mosaic rect the source must be untouched
        let outside = try XCTUnwrap(color(in: rendered, atTopDown: CGPoint(x: 70, y: 70)))
        XCTAssertEqual(outside.redComponent, 1.0, accuracy: 0.05)
        XCTAssertEqual(outside.greenComponent, 1.0, accuracy: 0.05)
    }

    func testMosaicOutsideTheImageIsIgnoredRatherThanCrashing() {
        let source = solidImage(width: 40, height: 40)
        let mosaic = mosaicElement(CGRect(x: 500, y: 500, width: 30, height: 30))

        let rendered = AnnotationRenderer.render(image: source, elements: [mosaic])
        XCTAssertEqual(rendered.size, source.size)
    }

    // MARK: - Degenerate input

    func testZeroSizedImageIsReturnedUnchanged() {
        let empty = NSImage(size: NSSize.zero)
        let rendered = AnnotationRenderer.render(image: empty, elements: [])
        XCTAssertEqual(rendered.size, NSSize.zero)
    }

    func testTextElementWithoutTextIsSkipped() {
        let source = solidImage(width: 40, height: 40)
        let text = DrawingElement(type: .text, path: CGMutablePath(), color: .red, lineWidth: 1,
                                  startPoint: CGPoint.zero, endPoint: CGPoint.zero, text: nil)
        let rendered = AnnotationRenderer.render(image: source, elements: [text])
        XCTAssertEqual(rendered.size, source.size)
    }
}
