import XCTest
import AppKit
import SwiftUI
@testable import VeloxClip

/// Renders Settings offscreen so layout regressions are visible.
/// VELOXCLIP_RENDER_SNAPSHOT=1 swift test --filter SettingsSnapshotTests
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    func testRenderPrivacySection() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VELOXCLIP_RENDER_SNAPSHOT"] == "1",
                          "snapshot rendering is opt-in")

        AppSettings.shared.blacklistUserAdded = ["com.bitwarden.desktop"]

        let view = SettingsView().frame(width: 720, height: 460)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 460)
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
        let path = "/tmp/veloxclip_settings.png"
        try png.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)

        AppSettings.shared.blacklistUserAdded = []
        print("SNAPSHOT: \(path)")
    }
}
