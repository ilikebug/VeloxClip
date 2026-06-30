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
            // The three states differ in height; re-fit the panel to the current
            // content (preserving the configured corner position) on every change.
            refit()
        }
    }

    // Resize the panel to fit the current phase's content, then re-anchor it so
    // it stays pinned to the configured corner (a taller panel must not drift
    // off the bottom edge). Runs synchronously so our own move isn't mistaken
    // for a user drag.
    private func refit() {
        guard let panel, let hosting else { return }
        let fitted = hosting.sizeThatFits(in: NSSize(width: 800, height: 600))
        isRepositioningProgrammatically = true
        panel.setContentSize(fitted)
        panel.setFrameOrigin(targetOrigin(for: panel.frame.size))
        isRepositioningProgrammatically = false
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
            // The HUD view has a fixed frame; size the panel once at creation
            panel.setContentSize(hosting.sizeThatFits(in: NSSize(width: 800, height: 300)))
            self.hosting = hosting
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false

            // Must run SYNCHRONOUSLY: a deferred Task lands after the
            // isRepositioningProgrammatically flag is reset, so our own
            // setFrameOrigin would be misread as a user drag and clobber the
            // position setting back to "custom" on every show
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: panel,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    PasteStackHUDController.shared.panelDidMove()
                }
            }

            self.panel = panel
        }

        guard let panel else { return }
        isRepositioningProgrammatically = true
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
                let pt = NSPoint(x: x, y: y)
                // Only honor a saved drag position if it still lands on a connected
                // screen — otherwise (unplugged external display) fall through to a
                // corner so the HUD never opens off-screen.
                let rect = NSRect(origin: pt, size: size)
                if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                    return pt
                }
            }
        }
        let activeScreen = NSScreen.activeOrMain
        let screen = activeScreen?.visibleFrame ?? .zero
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
        case "topCenter": // 50px down from the physical top edge of the screen
            let full = activeScreen?.frame ?? screen
            return NSPoint(x: full.midX - size.width / 2, y: full.maxY - size.height - 50)
        default: // bottomCenter
            return NSPoint(x: screen.midX - size.width / 2, y: screen.minY + margin)
        }
    }
}

struct PasteStackHUDView: View {
    @ObservedObject var stack = PasteStackService.shared
    @Environment(\.colorScheme) private var scheme

    // Kit panel width
    private let panelWidth: CGFloat = 240

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            switch stack.phase {
            case .active, .paused:
                progressContent(c)
            case .completed:
                completedContent(c)
            case .idle:
                EmptyView()
            }
        }
        .frame(width: panelWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(c.divider, lineWidth: 0.5)
        )
        .shadow(color: DesignSystem.panelShadow(scheme), radius: 25, x: 0, y: 9)
        .padding(10)
    }

    // MARK: - 进行中 / 暂停

    @ViewBuilder
    private func progressContent(_ c: DSColors) -> some View {
        let count = max(stack.queue.count, 1)
        let progressFrac = min(max(Double(stack.cursor) / Double(count), 0), 1)
        VStack(alignment: .leading, spacing: 0) {
            // Header: accent icon + title + n / m
            HStack(spacing: 7) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13))
                    .foregroundColor(c.accent)
                Text("Paste Stack")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.04 * 12)
                    .foregroundColor(c.text2)
                Spacer(minLength: 8)
                Text("\(min(stack.cursor + 1, stack.queue.count)) / \(stack.queue.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(c.text2)
            }
            .padding(.horizontal, 13)
            .padding(.top, 13)
            .padding(.bottom, 12)

            // Header bottom divider
            Rectangle()
                .fill(c.divider)
                .frame(height: 0.5)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.key)
                    Capsule().fill(c.accent)
                        .frame(width: geo.size.width * progressFrac)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 13)
            .padding(.top, 12)
            .padding(.bottom, 12)

            // Item list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(stack.queue.enumerated()), id: \.element.id) { index, item in
                    itemRow(index: index, item: item, c: c)
                }
            }
            .padding(.horizontal, 9)

            if stack.phase == .paused {
                pausedStrip(c)
                    .padding(.top, 12)
            } else {
                Color.clear.frame(height: 13)
            }
        }
    }

    @ViewBuilder
    private func itemRow(index: Int, item: ClipboardItem, c: DSColors) -> some View {
        let isCurrent = index == stack.cursor
        let isDone = index < stack.cursor

        HStack(spacing: 8) {
            // Index badge: 18×18, cornerRadius 5
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isCurrent ? c.accent : c.chip)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(c.accent)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isCurrent ? .white : c.text2)
                }
            }
            .frame(width: 18, height: 18)

            Text(shortLabel(item))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(c.text)

            Spacer(minLength: 4)

            if isCurrent {
                Text("↵")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(c.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(c.card))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? c.accentSoft : Color.clear)
        )
        .opacity(isDone ? 0.42 : 1)
    }

    // 暂停 — 检测到新复制
    @ViewBuilder
    private func pausedStrip(_ c: DSColors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("已暂停 — 你复制了新内容")
                    .font(.system(size: 11.5))
                    .foregroundColor(c.text)
                    .lineSpacing(11.5 * 0.4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.15))

            HStack(spacing: 8) {
                Button(action: { stack.resume() }) {
                    Text("继续").frame(maxWidth: .infinity)
                }
                .dsButton(.prominent)

                Button(action: { stack.cancel() }) {
                    Text("放弃").frame(maxWidth: .infinity)
                }
                .dsButton(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 完成

    @ViewBuilder
    private func completedContent(_ c: DSColors) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(c.accent)
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 18)

            Text("已粘贴 \(stack.queue.count) 项")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(c.text)
                .padding(.top, 12)

            Text("序列完成")
                .font(.system(size: 12))
                .foregroundColor(c.text2)
                .padding(.top, 2)

            Text("位置可在设置中改 · 默认底部居中")
                .font(.system(size: 11.5))
                .foregroundColor(c.text2)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func shortLabel(_ item: ClipboardItem) -> String {
        if let content = item.content, !content.isEmpty {
            return String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        }
        return item.localizedTypeName
    }
}
