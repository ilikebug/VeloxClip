import AppKit
import Combine
import ApplicationServices

enum PasteStackPhase: Equatable {
    case idle
    case active
    case paused
    case completed
}

// Sequential paste queue: stage items from the history overlay, then each
// observed Cmd+V pastes the next item. The service pre-writes the current
// item to the pasteboard and advances when a passive global key monitor sees
// Cmd+V — it never intercepts or injects events itself.
// See docs/superpowers/specs/2026-06-12-paste-stack-design.md
@MainActor
final class PasteStackService: ObservableObject {
    static let shared = PasteStackService(writer: SystemPasteboardWriter())

    @Published private(set) var phase: PasteStackPhase = .idle
    @Published private(set) var staged: [ClipboardItem] = []
    @Published private(set) var queue: [ClipboardItem] = []
    @Published private(set) var cursor: Int = 0

    private let writer: any PasteboardWriting
    private let permissionCheck: () -> Bool
    private let installsKeyMonitor: Bool
    private var keyMonitor: Any?
    private var lastWriteChangeCount: Int = -1
    private var initialSnapshot: PasteboardSnapshot?
    private var userWroteDuringStack = false

    init(writer: any PasteboardWriting,
         permissionCheck: @escaping () -> Bool = PasteStackService.checkAccessibilityPrompting,
         installsKeyMonitor: Bool = true) {
        self.writer = writer
        self.permissionCheck = permissionCheck
        self.installsKeyMonitor = installsKeyMonitor
    }

    // MARK: - Staging (overlay open, phase == .idle)

    func stagedIndex(of id: UUID) -> Int? {
        staged.firstIndex { $0.id == id }
    }

    func toggleStaged(_ item: ClipboardItem) {
        guard phase == .idle else { return }
        if let index = stagedIndex(of: item.id) {
            staged.remove(at: index)
        } else {
            staged.append(item)
        }
    }

    // MARK: - Lifecycle

    // Same prompt flow as screenshot/paste injection: when the permission is
    // missing, macOS shows its own dialog guiding the user to System Settings →
    // Privacy & Security → Accessibility
    nonisolated static func checkAccessibilityPrompting() -> Bool {
        if AXIsProcessTrusted() { return true }
        // kAXTrustedCheckOptionPrompt is a mutable global the Swift 6 checker rejects;
        // its value is the literal below
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }

    // Called when the overlay hides. No-op unless something is staged.
    func startIfStaged() async {
        guard phase == .idle, !staged.isEmpty else { return }
        guard permissionCheck() else {
            // Keep the staged items — once the user grants permission, closing
            // the overlay again retries without re-staging
            return
        }

        var items = staged
        staged.removeAll()
        // Blobs are lazy-loaded from the DB; queue items must be self-contained
        for index in items.indices where items[index].data == nil
            && (items[index].type == "image" || items[index].type == "rtf") {
            items[index].data = await ClipboardStore.shared.loadData(for: items[index].id)
        }

        queue = items
        cursor = 0
        userWroteDuringStack = false
        initialSnapshot = writer.capture()
        phase = .active
        writeCurrent()
        installKeyMonitorIfNeeded()
    }

    func resume() {
        guard phase == .paused else { return }
        writeCurrent()
        phase = .active
    }

    func cancel() {
        guard phase == .active || phase == .paused else { return }
        finish()
    }

    // Production: scheduled 1s after .completed. Internal so tests call it directly.
    func finalizeCompletion() {
        guard phase == .completed else { return }
        finish()
    }

    // MARK: - Advancing

    // Called (after a small delay) when the global monitor observes Cmd+V.
    func advanceAfterObservedPaste() {
        guard phase == .active else { return }
        // The pasteboard must still hold our write; otherwise the user copied
        // something the poll-based monitor hasn't reported yet — pause.
        guard writer.changeCount == lastWriteChangeCount else {
            noteExternalClipboardChange()
            return
        }
        if cursor + 1 >= queue.count {
            phase = .completed
            scheduleCompletionFinalize()
        } else {
            cursor += 1
            writeCurrent()
        }
    }

    // Called by ClipboardMonitor when it sees a non-self pasteboard write.
    func noteExternalClipboardChange() {
        guard phase == .active else { return }
        userWroteDuringStack = true
        phase = .paused
    }

    // MARK: - Private

    private func writeCurrent() {
        writer.write(queue[cursor])
        lastWriteChangeCount = writer.changeCount
    }

    private func finish() {
        if !userWroteDuringStack, let snapshot = initialSnapshot {
            writer.restore(snapshot)
        }
        queue = []
        cursor = 0
        initialSnapshot = nil
        userWroteDuringStack = false
        phase = .idle
        removeKeyMonitor()
    }

    private func scheduleCompletionFinalize() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.finalizeCompletion()
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard installsKeyMonitor, keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let isCommandV = event.keyCode == 0x09
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && !event.isARepeat
            guard isCommandV else { return }
            Task { @MainActor in
                guard PasteStackService.shared.phase == .active else { return }
                // Give the target app time to read the pasteboard before swapping
                try? await Task.sleep(nanoseconds: 150_000_000)
                PasteStackService.shared.advanceAfterObservedPaste()
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
