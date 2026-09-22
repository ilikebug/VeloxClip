import AppKit
import SwiftUI

/// Composites annotations onto a screenshot.
///
/// This was three private methods on a 732-line `struct View`, which put the
/// parts most likely to regress silently — Retina pixel sizing, the Core
/// Graphics coordinate flip, mosaic mirroring — out of reach of tests. It is
/// pure: no SwiftUI view state, no AppSettings, no design system.
enum AnnotationRenderer {
    /// How much the mosaic shrinks a region before scaling it back up.
    static let pixelationFactor: CGFloat = 15

    /// Draws `elements` over `image` and returns a new image.
    /// Falls back to the original if a bitmap context cannot be made.
    static func render(image: NSImage, elements: [DrawingElement]) -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        // image.size is in points; Retina screenshots carry 2x pixels. Size the bitmap
        // by true pixel dimensions or the export loses half its resolution.
        let repPixelsWide = image.representations.map(\.pixelsWide).max() ?? 0
        let repPixelsHigh = image.representations.map(\.pixelsHigh).max() ?? 0
        let pixelsWide = repPixelsWide > 0 ? repPixelsWide : Int(imageSize.width)
        let pixelsHigh = repPixelsHigh > 0 ? repPixelsHigh : Int(imageSize.height)

        // Bitmap/context creation can fail on extreme dimensions or memory pressure —
        // fall back to the unedited image instead of crashing on a force unwrap
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            print("❌ Failed to create bitmap context for edited image, returning original")
            return image
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let context = graphicsContext.cgContext

        // Map user space to points so all drawing below (image, annotations,
        // line widths, font sizes) lands on the full pixel raster
        context.saveGState()
        context.scaleBy(x: CGFloat(pixelsWide) / imageSize.width, y: CGFloat(pixelsHigh) / imageSize.height)

        image.draw(in: NSRect(origin: .zero, size: imageSize))

        context.saveGState()

        // Flip coordinate system: SwiftUI uses top-down (Y=0 at top), Core Graphics uses bottom-up (Y=0 at bottom)
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1.0, y: -1.0)

        for element in elements {
            switch element.type {
            case .text:
                if let text = element.text, let fontSize = element.fontSize {
                    // Text rendering requires special handling
                    context.saveGState()

                    // Move to text position
                    context.translateBy(x: element.startPoint.x, y: element.startPoint.y)
                    // Flip back so text appears right-side up
                    context.scaleBy(x: 1.0, y: -1.0)

                    let textColor = NSColor(element.color.opacity(element.opacity))
                    let font = NSFont.systemFont(ofSize: fontSize)
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                    let attributedString = NSAttributedString(string: text, attributes: attributes)
                    // Canvas preview centers text on its point — anchor the export the same way
                    let textSize = attributedString.size()
                    attributedString.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))

                    context.restoreGState()
                }
            case .mosaic:
                if let rect = element.rect {
                    applyMosaicEffect(to: context, source: image, rect: rect)
                }
            default:
                let strokeColor = NSColor(element.color.opacity(element.opacity)).cgColor
                context.setStrokeColor(strokeColor)
                context.setLineWidth(element.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(element.path)

                if element.type == .highlight {
                    context.setFillColor(NSColor(element.color.opacity(element.opacity * 0.3)).cgColor)
                    context.fillPath()
                    context.addPath(element.path)
                } else if element.type == .arrow {
                    context.setFillColor(NSColor(element.color.opacity(element.opacity)).cgColor)
                    context.fillPath()
                    context.addPath(element.path)
                }
                context.strokePath()
            }
        }

        context.restoreGState() // flip
        context.restoreGState() // points→pixels scale
        NSGraphicsContext.restoreGraphicsState()

        // Report the rep in points so the NSImage keeps its 2x backing scale
        bitmapRep.size = imageSize
        let finalImage = NSImage(size: imageSize)
        finalImage.addRepresentation(bitmapRep)
        return finalImage
    }

    /// Pixelates the source region under `pointRect` (top-down, point coordinates).
    /// CGImage cropping operates on bitmap rows (top-left origin) in PIXELS — on Retina
    /// the backing CGImage is 2x the point size, so the rect must be scaled before cropping.
    static func pixelatedPatch(of image: NSImage, forPointRect pointRect: CGRect) -> CGImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let clamped = pointRect.intersection(CGRect(origin: .zero, size: image.size))
        guard clamped.width > 0, clamped.height > 0 else { return nil }

        let pxScaleX = CGFloat(cgImage.width) / image.size.width
        let pxScaleY = CGFloat(cgImage.height) / image.size.height
        let cropRect = CGRect(
            x: clamped.origin.x * pxScaleX,
            y: clamped.origin.y * pxScaleY,
            width: clamped.width * pxScaleX,
            height: clamped.height * pxScaleY
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        let smallSize = CGSize(
            width: max(1, clamped.width / pixelationFactor),
            height: max(1, clamped.height / pixelationFactor)
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let smallContext = CGContext(data: nil, width: Int(smallSize.width), height: Int(smallSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        smallContext.interpolationQuality = .none
        smallContext.draw(croppedCGImage, in: CGRect(origin: .zero, size: smallSize))
        return smallContext.makeImage()
    }

    private static func applyMosaicEffect(to context: CGContext, source: NSImage, rect: CGRect) {
        // rect is top-down (same space the user drew in) — pixelatedPatch handles cropping
        guard let pixelatedImage = pixelatedPatch(of: source, forPointRect: rect) else { return }

        context.saveGState()
        context.interpolationQuality = .none
        // The export context is flipped to top-down; CGContext.draw renders images
        // bottom-up, so mirror around the rect's center to keep the patch upright
        context.translateBy(x: 0, y: rect.midY)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: 0, y: -rect.midY)
        context.draw(pixelatedImage, in: rect)
        context.restoreGState()
    }
}
