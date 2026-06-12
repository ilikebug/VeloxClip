import SwiftUI
import AppKit
import Combine

// Non-activating floating panel showing paste-stack progress. Shown/hidden by
// observing PasteStackService.phase; never steals focus from the target app.
@MainActor
final class PasteStackHUDController {
    static let shared = PasteStackHUDController()

    private var panel: NSPanel?
    private var hosting: NSHostingController<PasteStackHUDView>?
    private var cancellables: Set<AnyCancellable> = []
    private var isRepositioningProgrammatically = false

    private init() {}

    // Call once at app launch
    func activate() {
        PasteStackService.shared.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.phaseChanged(phase)
            }
            .store(in: &cancellables)

        AppSettings.shared.$showPasteStackHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                if !show {
                    self?.hide()
                } else if PasteStackService.shared.phase != .idle {
                    self?.show()
                }
            }
            .store(in: &cancellables)
    }

    private func phaseChanged(_ phase: PasteStackPhase) {
        if phase == .idle {
            hide()
        } else if AppSettings.shared.showPasteStackHUD {
            show()
        }
    }

    private func show() {
        if panel == nil {
            let hosting = NSHostingController(rootView: PasteStackHUDView())
            hosting.sizingOptions = []
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            // The hosting view must NOT be the window's contentView — AppKit then
            // routes its display cycle through NSHostingView's window-sizing
            // machinery, which mutates constraints mid-pass and throws
            // NSInternalInconsistencyException. A plain container breaks that link.
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 64))
            hosting.view.frame = container.bounds
            hosting.view.autoresizingMask = [.width, .height]
            container.addSubview(hosting.view)
            panel.contentView = container
            self.hosting = hosting
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false

            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: panel,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    PasteStackHUDController.shared.panelDidMove()
                }
            }

            self.panel = panel
        }

        guard let panel else { return }
        // Re-measure on every phase change — the paused state is wider than
        // the active one, and a fixed frame would clip its buttons. With
        // sizingOptions disabled, fittingSize is meaningless; sizeThatFits
        // measures the SwiftUI content directly
        isRepositioningProgrammatically = true
        if let hosting {
            panel.setContentSize(hosting.sizeThatFits(in: NSSize(width: 800, height: 300)))
        }
        panel.setFrameOrigin(targetOrigin(for: panel.frame.size))
        isRepositioningProgrammatically = false
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func panelDidMove() {
        guard !isRepositioningProgrammatically, let panel, panel.isVisible else { return }
        let origin = panel.frame.origin
        AppSettings.shared.pasteStackHUDCustomOrigin = "\(Int(origin.x)),\(Int(origin.y))"
        AppSettings.shared.pasteStackHUDPosition = "custom"
    }

    private func targetOrigin(for size: NSSize) -> NSPoint {
        let settings = AppSettings.shared
        if settings.pasteStackHUDPosition == "custom" {
            let parts = settings.pasteStackHUDCustomOrigin.split(separator: ",")
            if parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) {
                return NSPoint(x: x, y: y)
            }
        }
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 16
        switch settings.pasteStackHUDPosition {
        case "bottomLeft":
            return NSPoint(x: screen.minX + margin, y: screen.minY + margin)
        case "bottomRight":
            return NSPoint(x: screen.maxX - size.width - margin, y: screen.minY + margin)
        case "topRight":
            return NSPoint(x: screen.maxX - size.width - margin, y: screen.maxY - size.height - margin)
        case "topLeft":
            return NSPoint(x: screen.minX + margin, y: screen.maxY - size.height - margin)
        default: // topCenter — 50px down from the physical top edge of the screen
            let full = NSScreen.main?.frame ?? screen
            return NSPoint(x: full.midX - size.width / 2, y: full.maxY - size.height - 50)
        }
    }
}

struct PasteStackHUDView: View {
    @ObservedObject var stack = PasteStackService.shared

    var body: some View {
        HStack(spacing: 10) {
            switch stack.phase {
            case .active:
                Image(systemName: "list.number")
                    .foregroundStyle(DesignSystem.primaryGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next: \(currentPreview)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text("Press ⌘V to paste")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                progressLabel
                closeButton
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paused")
                        .font(.system(size: 12, weight: .medium))
                    Text("You copied something new")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                progressLabel
                Button(action: { stack.resume() }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .help("Resume the paste queue")
                closeButton
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Done")
                    .font(.system(size: 12, weight: .medium))
                progressLabel
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 230)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(6)
    }

    private var progressLabel: some View {
        Text("\(min(stack.cursor + 1, stack.queue.count))/\(stack.queue.count)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
    }

    private var closeButton: some View {
        Button(action: { stack.cancel() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Exit the paste queue")
    }

    private var currentPreview: String {
        guard stack.cursor < stack.queue.count else { return "" }
        let item = stack.queue[stack.cursor]
        if let content = item.content, !content.isEmpty {
            return String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        }
        switch item.type {
        case "image": return "Image"
        case "rtf": return "Rich Text"
        default: return item.type
        }
    }
}
