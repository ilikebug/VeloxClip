import XCTest
import AppKit
import SwiftUI
@testable import VeloxClip

/// Renders the colour preview offscreen so the displayed values can be read.
/// VELOXCLIP_RENDER_SNAPSHOT=1 swift test --filter ColorPreviewSnapshotTests
@MainActor
final class ColorPreviewSnapshotTests: XCTestCase {
    func testRenderColorPreview() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VELOXCLIP_RENDER_SNAPSHOT"] == "1",
                          "snapshot rendering is opt-in")

        // #0B0C0D is the case the review caught: it used to display as #0A0B0C
        let view = ColorPreviewView(colorString: "#0B0C0D").frame(width: 520, height: 560)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 560)
        window.contentView = hosting
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        hosting.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let path = "/tmp/veloxclip_color_preview.png"
        try png.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
        print("SNAPSHOT: \(path)")
    }
}
