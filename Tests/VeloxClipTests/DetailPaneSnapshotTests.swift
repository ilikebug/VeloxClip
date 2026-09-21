import XCTest
import AppKit
import SwiftUI
@testable import VeloxClip

/// Renders the real detail pane offscreen so layout regressions are visible.
/// Set VELOXCLIP_RENDER_SNAPSHOT=1 to write the PNG; otherwise skipped.
@MainActor
final class DetailPaneSnapshotTests: XCTestCase {
    func testRenderJSONDetailPane() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VELOXCLIP_RENDER_SNAPSHOT"] == "1",
                          "snapshot rendering is opt-in")

        let json = """
        {"name":"VeloxClip","version":"3.0.0","platform":{"os":"macOS","min":"14.0"},"features":["clipboard","ocr","paste-stack"],"counts":{"tests":254,"files":60}}
        """
        var item = ClipboardItem(type: "text", content: json, sourceApp: "Xcode")
        item.tags = ["JSON"]

        let view = PreviewView(item: item, onBack: {}, onClose: {})
            .frame(width: 560, height: 520)

        // .task/.onAppear only fire for a view inside a window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 520)
        window.contentView = hosting
        window.orderFrontRegardless()

        // Give the debounce + JSON parse time to land
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        hosting.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let path = "/tmp/veloxclip_json_detail.png"
        try png.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
        print("SNAPSHOT: \(path)")
    }
}
