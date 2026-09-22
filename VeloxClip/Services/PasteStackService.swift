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
    private let quietPermissionCheck: () -> Bool
    private let loadBlob: (UUID) async -> Data?
    private let installsKeyMonitor: Bool
    private var keyMonitor: Any?
    private var lastWriteChangeCount: Int = -1
    private var initialSnapshot: PasteboardSnapshot?
    private var userWroteDuringStack = false
    private var pendingAdvance: Task<Void, Never>?
    private var accessibilityPromptShown = false
    // Loading blobs suspends, and `staged`/`phase` only change after it — without
    // this a second caller (two hideOverlay paths in one runloop turn) would slip
    // through the guard and restart the stack over its own pasteboard write
    private var isStarting = false

    /// `permissionCheck` may show the system dialog; `quietPermissionCheck` never does
    /// and is used for every retry after the first denial.
    init(writer: any PasteboardWriting,
         permissionCheck: @escaping () -> Bool = PasteStackService.checkAccessibilityPrompting,
         quietPermissionCheck: @escaping () -> Bool = { AccessibilityPermission.isGranted },
         loadBlob: @escaping (UUID) async -> Data? = { await ClipboardStore.shared.loadData(for: $0) },
         installsKeyMonitor: Bool = true) {
        self.writer = writer
        self.permissionCheck = permissionCheck
        self.quietPermissionCheck = quietPermissionCheck
        self.loadBlob = loadBlob
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

    func clearStaged() {
        guard phase == .idle else { return }
        staged.removeAll()
    }

    // MARK: - Lifecycle

    // Accessibility prompting policy lives in AccessibilityPermission, shared
    // with WindowManager's paste-injection path. This used to be a byte-for-byte
    // duplicate of that code, and only this copy had the once-per-session guard.
    nonisolated static func checkAccessibilityPrompting() -> Bool {
        MainActor.assumeIsolated { AccessibilityPermission.promptIfNeeded() }
    }

    // Called when the overlay hides. No-op unless something is staged.
    func startIfStaged() async {
        guard phase == .idle, !staged.isEmpty, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        // Keep the staged items when permission is missing — once the user
        // grants it, closing the overlay again retries without re-staging.
        // The prompting check runs once per session; hideOverlay fires on every
        // app deactivation and used to re-open the system dialog each time.
        if accessibilityPromptShown {
            guard quietPermissionCheck() else { return }
        } else if !permissionCheck() {
            accessibilityPromptShown = true
            return
        }

        var items = staged
        // Blobs are lazy-loaded from the DB; queue items must be self-contained
        for index in items.indices where items[index].data == nil
            && (items[index].type == "image" || items[index].type == "rtf") {
            items[index].data = await loadBlob(items[index].id)
        }
        // Drop items with nothing to paste (blob deleted from history after
        // staging) — pasting them would silently re-paste the previous item
        items.removeAll { !$0.hasPasteablePayload }
        // Nothing left: keep the staging rather than discarding it silently
        guard !items.isEmpty else { return }

        staged.removeAll()
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

    // The global monitor saw Cmd+V. A second key event before the settle delay
    // elapses (a quick double paste) joins the pending advance instead of
    // scheduling another — two independent advances skipped an item.
    func noteObservedPaste() {
        guard phase == .active, pendingAdvance == nil else { return }
        pendingAdvance = Task { @MainActor in
            // Give the target app time to read the pasteboard before swapping
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }   // finish() ran meanwhile
            self.pendingAdvance = nil
            self.advanceAfterObservedPaste()
        }
    }

    // Called (after a small delay) when the global monitor observes Cmd+V.
    func advanceAfterObservedPaste() {
        guard phase == .active else { return }
        // The pasteboard must still hold our write; otherwise something else
        // wrote to it and the poll-based monitor hasn't reported yet — pause.
        guard writer.changeCount == lastWriteChangeCount else {
            pauseForForeignWrite()
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

    // Called on any pasteboard change. Pauses unless the change is the
    // stack's own write — this covers user copies AND the app's other
    // pasteboard writers (text capture, Copy Text, single-item paste).
    func noteClipboardChange() {
        guard writer.changeCount != lastWriteChangeCount else { return }
        switch phase {
        case .active:
            pauseForForeignWrite()
        case .completed:
            // The stack sits in .completed for a second showing "done", which
            // is a natural moment to copy the next thing. Guarding on .active
            // meant that copy was not recorded, so finish() restored the
            // pre-stack pasteboard over it a second later. Pausing a finished
            // stack would be wrong — just record the write so the restore is
            // suppressed.
            userWroteDuringStack = true
        case .idle, .paused:
            break
        }
    }

    private func pauseForForeignWrite() {
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
        pendingAdvance?.cancel()
        pendingAdvance = nil
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
        // Route through `self`, not `.shared`: any non-shared instance built
        // with installsKeyMonitor: true used to drive the singleton's state
        // machine instead of its own.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isCommandV = event.keyCode == 0x09
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && !event.isARepeat
            guard isCommandV else { return }
            Task { @MainActor in
                self?.noteObservedPaste()
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
