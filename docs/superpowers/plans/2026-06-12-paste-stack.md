# Paste Stack (顺序粘贴队列) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stage multiple clipboard history items, then paste them one-by-one into any app using only repeated Cmd+V, with a floating HUD showing progress.

**Architecture:** A `@MainActor PasteStackService` state machine (idle → active ⇄ paused → completed) pre-writes the current queue item to the pasteboard and advances when a passive global key monitor observes Cmd+V. Pasteboard writes go through the existing `PasteboardSelfWriteGate` so `ClipboardMonitor` never re-ingests them; conversely the monitor notifies the service on external (user) writes, which pauses the stack. A non-activating `NSPanel` HUD shows progress. The pasteboard side is abstracted behind a `PasteboardWriting` protocol so the state machine is unit-testable with a fake.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (NSPanel, NSEvent monitors), XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-06-12-paste-stack-design.md`

**Spec deviations (agreed rationale, baked into this plan):**
1. The spec says "Space stages the selected row". The search field is always focused in `MainView`, so Space must still type into a non-empty query. Implementation: **Space stages only when the search field is empty**; a trailing ⊕ button on each row works always.
2. `WindowManager.injectPasteEvent` posts Cmd+V via `postToPid`, which does NOT pass through global event monitors — so the app's own single-item paste cannot falsely advance the stack. No extra guard needed.

**File map:**
- Create: `VeloxClip/Services/PasteStackPasteboard.swift` (protocol + snapshot + real writer)
- Create: `VeloxClip/Services/PasteStackService.swift` (state machine + key monitor)
- Create: `VeloxClip/Views/PasteStackHUD.swift` (panel controller + SwiftUI view)
- Create: `Tests/VeloxClipTests/PasteStackServiceTests.swift`
- Modify: `VeloxClip/Models/AppSettings.swift` (2 new settings)
- Modify: `VeloxClip/Views/SettingsView.swift` (Paste Stack section)
- Modify: `VeloxClip/Services/ClipboardMonitor.swift` (1-line external-change hook)
- Modify: `VeloxClip/App/WindowManager.swift` (central `hideOverlay()` + start hook)
- Modify: `VeloxClip/Views/MainView.swift` (Space key)
- Modify: `VeloxClip/Views/ClipboardListView.swift` (⊕ button + ①②③ badge)
- Modify: `VeloxClip/App/VeloxClipApp.swift` (menu-bar progress label + HUD controller activation)
- Modify: `CLAUDE.md` (document the new service)

---

### Task 1: Pasteboard abstraction (`PasteboardWriting` + `PasteboardSnapshot`)

**Files:**
- Create: `VeloxClip/Services/PasteStackPasteboard.swift`
- Test: `Tests/VeloxClipTests/PasteStackServiceTests.swift` (snapshot round-trip tests)

- [ ] **Step 1: Write the failing tests**

Create `Tests/VeloxClipTests/PasteStackServiceTests.swift`:

```swift
import XCTest
import AppKit
@testable import VeloxClip

final class PasteboardSnapshotTests: XCTestCase {
    // A uniquely named pasteboard isolates tests from the system clipboard
    private func makeTestPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("velox-test-\(UUID().uuidString)"))
    }

    @MainActor
    func testCaptureAndRestoreRoundTripsStringContent() {
        let pb = makeTestPasteboard()
        pb.clearContents()
        pb.setString("before stack", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pb)
        XCTAssertNotNil(snapshot)

        pb.clearContents()
        pb.setString("queue item", forType: .string)

        snapshot?.restore(to: pb)
        XCTAssertEqual(pb.string(forType: .string), "before stack")
    }

    @MainActor
    func testCaptureOfEmptyPasteboardReturnsNil() {
        let pb = makeTestPasteboard()
        pb.clearContents()
        XCTAssertNil(PasteboardSnapshot.capture(from: pb))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PasteboardSnapshotTests 2>&1 | tail -5`
Expected: compile error — `PasteboardSnapshot` not defined.

- [ ] **Step 3: Implement**

Create `VeloxClip/Services/PasteStackPasteboard.swift`:

```swift
import AppKit

// Raw byte-level snapshot of the pasteboard's first item, used to put the
// user's pre-stack clipboard back when the stack finishes.
struct PasteboardSnapshot {
    let typedData: [(type: NSPasteboard.PasteboardType, data: Data)]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        let typedData = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
            guard let data = item.data(forType: type) else { return nil }
            return (type, data)
        }
        guard !typedData.isEmpty else { return nil }
        return PasteboardSnapshot(typedData: typedData)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        for (type, data) in typedData {
            item.setData(data, forType: type)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        PasteboardSelfWriteGate.shared.recordSelfWrite()
    }
}

// Seam between the PasteStack state machine and the real pasteboard,
// so the state machine is unit-testable with a fake.
@MainActor
protocol PasteboardWriting {
    var changeCount: Int { get }
    func write(_ item: ClipboardItem)
    func capture() -> PasteboardSnapshot?
    func restore(_ snapshot: PasteboardSnapshot)
}

@MainActor
final class SystemPasteboardWriter: PasteboardWriting {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func write(_ item: ClipboardItem) {
        // copyToPasteboard already records the self-write in the gate
        item.copyToPasteboard()
    }

    func capture() -> PasteboardSnapshot? {
        PasteboardSnapshot.capture(from: NSPasteboard.general)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        snapshot.restore(to: NSPasteboard.general)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PasteboardSnapshotTests 2>&1 | tail -5`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VeloxClip/Services/PasteStackPasteboard.swift Tests/VeloxClipTests/PasteStackServiceTests.swift
git commit -m "feat: pasteboard snapshot + writer seam for paste stack"
```

---

### Task 2: `PasteStackService` state machine (TDD)

**Files:**
- Create: `VeloxClip/Services/PasteStackService.swift`
- Test: `Tests/VeloxClipTests/PasteStackServiceTests.swift` (append)

State machine contract (from the spec):
- `idle` —staging→ `active` (start pre-writes item 0, captures snapshot)
- `active` —observed Cmd+V→ advance cursor + pre-write next, or → `completed` on last
- `active` —external clipboard write→ `paused` (sets `userWroteDuringStack`)
- `paused` —resume()→ re-writes current item → `active`
- `active`/`paused` —cancel()→ `idle` (+restore)
- `completed` —finalizeCompletion() (1s later in production)→ `idle` (+restore)
- Restore rule: restore the captured snapshot ONLY if the user never wrote to the clipboard during the stack.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/VeloxClipTests/PasteStackServiceTests.swift`:

```swift
@MainActor
final class FakePasteboardWriter: PasteboardWriting {
    private(set) var changeCount = 0
    private(set) var written: [ClipboardItem] = []
    private(set) var restoredCount = 0
    var snapshotToCapture: PasteboardSnapshot? =
        PasteboardSnapshot(typedData: [(.string, Data("before".utf8))])

    func write(_ item: ClipboardItem) {
        written.append(item)
        changeCount += 1
    }
    func capture() -> PasteboardSnapshot? { snapshotToCapture }
    func restore(_ snapshot: PasteboardSnapshot) {
        restoredCount += 1
        changeCount += 1
    }
    func simulateExternalWrite() { changeCount += 1 }
}

@MainActor
final class PasteStackServiceTests: XCTestCase {
    private var writer: FakePasteboardWriter!
    private var service: PasteStackService!

    override func setUp() async throws {
        writer = FakePasteboardWriter()
        service = PasteStackService(
            writer: writer,
            permissionCheck: { true },
            installsKeyMonitor: false
        )
    }

    private func makeItems(_ count: Int) -> [ClipboardItem] {
        (0..<count).map { ClipboardItem(type: "text", content: "item-\($0)") }
    }

    func testToggleStagedAddsAndRemovesInOrder() {
        let items = makeItems(3)
        items.forEach { service.toggleStaged($0) }
        XCTAssertEqual(service.staged.map(\.id), items.map(\.id))
        XCTAssertEqual(service.stagedIndex(of: items[1].id), 1)

        service.toggleStaged(items[0])
        XCTAssertEqual(service.staged.map(\.id), [items[1].id, items[2].id])
        XCTAssertEqual(service.stagedIndex(of: items[1].id), 0)
        XCTAssertNil(service.stagedIndex(of: items[0].id))
    }

    func testStartWritesFirstItemAndActivates() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }

        await service.startIfStaged()

        XCTAssertEqual(service.phase, .active)
        XCTAssertTrue(service.staged.isEmpty)
        XCTAssertEqual(service.queue.count, 2)
        XCTAssertEqual(service.cursor, 0)
        XCTAssertEqual(writer.written.map(\.content), ["item-0"])
    }

    func testStartWithNothingStagedDoesNothing() async {
        await service.startIfStaged()
        XCTAssertEqual(service.phase, .idle)
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testStartWithoutPermissionStaysIdleAndClearsStaging() async {
        let denied = PasteStackService(
            writer: writer, permissionCheck: { false }, installsKeyMonitor: false)
        denied.toggleStaged(makeItems(1)[0])

        await denied.startIfStaged()

        XCTAssertEqual(denied.phase, .idle)
        XCTAssertTrue(denied.staged.isEmpty)
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testObservedPasteAdvancesAndWritesNext() async {
        let items = makeItems(3)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        service.advanceAfterObservedPaste()

        XCTAssertEqual(service.cursor, 1)
        XCTAssertEqual(service.phase, .active)
        XCTAssertEqual(writer.written.map(\.content), ["item-0", "item-1"])
    }

    func testObservedPasteOnLastItemCompletes() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        service.advanceAfterObservedPaste()
        service.advanceAfterObservedPaste()

        XCTAssertEqual(service.phase, .completed)
        // cursor stays on the last item so HUD shows n/n
        XCTAssertEqual(service.cursor, 1)
    }

    func testFinalizeCompletionRestoresSnapshotAndGoesIdle() async {
        let items = makeItems(1)
        service.toggleStaged(items[0])
        await service.startIfStaged()
        service.advanceAfterObservedPaste()
        XCTAssertEqual(service.phase, .completed)

        service.finalizeCompletion()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(writer.restoredCount, 1)
    }

    func testChangeCountMismatchPausesInsteadOfAdvancing() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        writer.simulateExternalWrite()
        service.advanceAfterObservedPaste()

        XCTAssertEqual(service.phase, .paused)
        XCTAssertEqual(service.cursor, 0)
        XCTAssertEqual(writer.written.count, 1)
    }

    func testExternalChangeNotePausesAndResumeRewritesCurrent() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        service.noteExternalClipboardChange()
        XCTAssertEqual(service.phase, .paused)

        service.resume()
        XCTAssertEqual(service.phase, .active)
        XCTAssertEqual(writer.written.map(\.content), ["item-0", "item-0"])
    }

    func testNoRestoreWhenUserWroteDuringStack() async {
        let items = makeItems(1)
        service.toggleStaged(items[0])
        await service.startIfStaged()

        service.noteExternalClipboardChange()
        service.resume()
        service.advanceAfterObservedPaste()
        service.finalizeCompletion()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(writer.restoredCount, 0)
    }

    func testCancelRestoresAndGoesIdle() async {
        let items = makeItems(2)
        items.forEach { service.toggleStaged($0) }
        await service.startIfStaged()

        service.cancel()

        XCTAssertEqual(service.phase, .idle)
        XCTAssertEqual(writer.restoredCount, 1)
        XCTAssertTrue(service.queue.isEmpty)
    }

    func testStagingIgnoredWhileActive() async {
        let items = makeItems(2)
        service.toggleStaged(items[0])
        await service.startIfStaged()

        service.toggleStaged(items[1])
        XCTAssertTrue(service.staged.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PasteStackServiceTests 2>&1 | tail -5`
Expected: compile error — `PasteStackService` not defined.

- [ ] **Step 3: Implement the state machine**

Create `VeloxClip/Services/PasteStackService.swift`:

```swift
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
// observed Cmd+V pastes the next item. See docs/superpowers/specs/2026-06-12-paste-stack-design.md
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
         permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
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

    // Called when the overlay hides. No-op unless something is staged.
    func startIfStaged() async {
        guard phase == .idle, !staged.isEmpty else { return }
        guard permissionCheck() else {
            staged.removeAll()
            ErrorHandler.shared.handle(PasteStackError.accessibilityPermissionMissing)
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

enum PasteStackError: LocalizedError {
    case accessibilityPermissionMissing

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Paste Stack needs Accessibility permission to observe Cmd+V. Enable VeloxClip in System Settings → Privacy & Security → Accessibility."
        }
    }
}
```

Note: check `ErrorHandler.handle(_ error: Error)` exists at `VeloxClip/Services/ErrorHandler.swift:13` (it does — takes any `Error`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PasteStackServiceTests 2>&1 | tail -5`
Expected: all 12 tests pass.

- [ ] **Step 5: Run the full suite + build**

Run: `swift build -c debug 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .+ tests" | tail -1`
Expected: build succeeds, all tests pass (38 existing + 14 new).

- [ ] **Step 6: Commit**

```bash
git add VeloxClip/Services/PasteStackService.swift Tests/VeloxClipTests/PasteStackServiceTests.swift
git commit -m "feat: PasteStackService state machine with passive Cmd+V advance"
```

---

### Task 3: Wire into ClipboardMonitor and WindowManager

**Files:**
- Modify: `VeloxClip/Services/ClipboardMonitor.swift` (in `checkForChanges`, after the self-write gate)
- Modify: `VeloxClip/App/WindowManager.swift` (central hide + start hooks)

- [ ] **Step 1: Notify the service of external clipboard changes**

In `ClipboardMonitor.checkForChanges()`, the body currently ends with:

```swift
        if PasteboardSelfWriteGate.shared.isSelfWrite(changeCount: lastChangeCount) {
            return
        }

        processClippedContent()
```

Change to:

```swift
        if PasteboardSelfWriteGate.shared.isSelfWrite(changeCount: lastChangeCount) {
            return
        }

        // A non-self write means the user copied something — the paste stack
        // must yield (pause) instead of fighting over the pasteboard
        PasteStackService.shared.noteExternalClipboardChange()

        processClippedContent()
```

- [ ] **Step 2: Centralize overlay hiding and start the stack on hide**

In `WindowManager`, add a method and reroute every hide path through it.

Add after `toggleWindow()`:

```swift
    func hideOverlay() {
        window?.orderOut(nil)
        Task { @MainActor in
            await PasteStackService.shared.startIfStaged()
        }
    }
```

Then replace the hide call sites:

1. `toggleWindow()` — replace `window.orderOut(nil)` with `hideOverlay()`:

```swift
    func toggleWindow() {
        if let window = window, window.isVisible {
            hideOverlay()
        } else {
            showWindow()
        }
    }
```

2. The `didResignActiveNotification` observer in `init` — replace `WindowManager.shared.window?.orderOut(nil)` with `WindowManager.shared.hideOverlay()`.

3. `windowDidResignKey` — replace the final `window.orderOut(nil)` with `hideOverlay()`.

4. `OverlayWindow.cancelOperation` (Esc fallback) — replace `orderOut(nil)` with:

```swift
    override func cancelOperation(_ sender: Any?) {
        WindowManager.shared.hideOverlay()
    }
```

5. `selectAndPaste` — keep its direct `self.window?.orderOut(nil)` (the stack must NOT start before the in-flight injected paste lands). At the END of the `Task` body in `selectAndPaste` (after the `self.injectPasteEvent(to: app)` line), add:

```swift
            // If items are staged, start the stack only after the in-flight
            // injected paste has read the pasteboard
            try? await Task.sleep(nanoseconds: 300_000_000)
            await PasteStackService.shared.startIfStaged()
```

Also add the same start call to the early-return path (`guard let app = targetApp else`) — replace:

```swift
            guard let app = targetApp else {
                NSApp.hide(nil)
                return
            }
```

with:

```swift
            guard let app = targetApp else {
                NSApp.hide(nil)
                await PasteStackService.shared.startIfStaged()
                return
            }
```

Leave the `guard Self.ensureAccessibilityPermission() else { return }` line unchanged — without the permission the stack cannot run either, and `startIfStaged` surfaces its own error if reached later.

- [ ] **Step 3: Build and run full tests**

Run: `swift build -c debug 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .+ tests" | tail -1`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add VeloxClip/Services/ClipboardMonitor.swift VeloxClip/App/WindowManager.swift
git commit -m "feat: wire paste stack into clipboard monitor and overlay lifecycle"
```

---

### Task 4: Settings (`AppSettings` + `SettingsView`)

**Files:**
- Modify: `VeloxClip/Models/AppSettings.swift`
- Modify: `VeloxClip/Views/SettingsView.swift`

- [ ] **Step 1: Add the two settings to AppSettings**

Follow the existing `@Published var … didSet` pattern. Add after `pasteImageShortcut`:

```swift
    @Published var showPasteStackHUD: Bool {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "showPasteStackHUD", value: String(showPasteStackHUD))
            }
        }
    }

    // "bottomRight" | "bottomLeft" | "topRight" | "topLeft" | "custom"
    @Published var pasteStackHUDPosition: String {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "pasteStackHUDPosition", value: pasteStackHUDPosition)
            }
        }
    }

    // "x,y" of the panel origin, set when the user drags the HUD
    @Published var pasteStackHUDCustomOrigin: String {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "pasteStackHUDCustomOrigin", value: pasteStackHUDCustomOrigin)
            }
        }
    }
```

In `init()`, add defaults before the `Task { await loadSettings() … }` block:

```swift
        self.showPasteStackHUD = true
        self.pasteStackHUDPosition = "bottomRight"
        self.pasteStackHUDCustomOrigin = ""
```

In `loadSettings()`, add (same shape as the existing blocks):

```swift
        if let show = await dbManager.getSetting(key: "showPasteStackHUD") {
            await MainActor.run { self.showPasteStackHUD = show == "true" }
        } else {
            try? await dbManager.setSetting(key: "showPasteStackHUD", value: "true")
        }

        if let position = await dbManager.getSetting(key: "pasteStackHUDPosition") {
            await MainActor.run { self.pasteStackHUDPosition = position }
        } else {
            try? await dbManager.setSetting(key: "pasteStackHUDPosition", value: "bottomRight")
        }

        if let origin = await dbManager.getSetting(key: "pasteStackHUDCustomOrigin") {
            await MainActor.run { self.pasteStackHUDCustomOrigin = origin }
        }
```

- [ ] **Step 2: Add the settings UI**

In `GeneralSettingsView` (in `VeloxClip/Views/SettingsView.swift`), add a new Section between the first Section and "Maintenance":

```swift
            Section("Paste Stack") {
                Toggle("Show Paste Stack HUD", isOn: $settings.showPasteStackHUD)
                    .help("Floating progress panel while a paste queue is active. When off, progress shows in the menu bar instead.")

                Picker("HUD Position", selection: $settings.pasteStackHUDPosition) {
                    Text("Bottom Right").tag("bottomRight")
                    Text("Bottom Left").tag("bottomLeft")
                    Text("Top Right").tag("topRight")
                    Text("Top Left").tag("topLeft")
                    if settings.pasteStackHUDPosition == "custom" {
                        Text("Custom (dragged)").tag("custom")
                    }
                }
                .disabled(!settings.showPasteStackHUD)
                .help("Picking a corner resets a dragged (custom) position")
            }
```

- [ ] **Step 3: Build, test, commit**

Run: `swift build -c debug 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .+ tests" | tail -1`
Expected: build succeeds, all tests pass.

```bash
git add VeloxClip/Models/AppSettings.swift VeloxClip/Views/SettingsView.swift
git commit -m "feat: paste stack HUD settings (toggle + position)"
```

---

### Task 5: HUD panel + view

**Files:**
- Create: `VeloxClip/Views/PasteStackHUD.swift`
- Modify: `VeloxClip/App/VeloxClipApp.swift` (activate controller at launch)

- [ ] **Step 1: Implement the HUD**

Create `VeloxClip/Views/PasteStackHUD.swift`:

```swift
import SwiftUI
import AppKit
import Combine

// Non-activating floating panel showing paste-stack progress. Shown/hidden by
// observing PasteStackService.phase; never steals focus from the target app.
@MainActor
final class PasteStackHUDController {
    static let shared = PasteStackHUDController()

    private var panel: NSPanel?
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
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hosting
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
        panel.layoutIfNeeded()
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
                return NSPoint(x: x, y: y)
            }
        }
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 16
        switch settings.pasteStackHUDPosition {
        case "bottomLeft":
            return NSPoint(x: screen.minX + margin, y: screen.minY + margin)
        case "topRight":
            return NSPoint(x: screen.maxX - size.width - margin, y: screen.maxY - size.height - margin)
        case "topLeft":
            return NSPoint(x: screen.minX + margin, y: screen.maxY - size.height - margin)
        default: // bottomRight
            return NSPoint(x: screen.maxX - size.width - margin, y: screen.minY + margin)
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
```

- [ ] **Step 2: Activate the controller at launch**

In `AppDelegate.applicationDidFinishLaunching` (in `VeloxClip/App/VeloxClipApp.swift`), after `ShortcutManager.shared.registerAllShortcuts()`, add:

```swift
        // Paste stack HUD reacts to PasteStackService phase changes
        Task { @MainActor in
            PasteStackHUDController.shared.activate()
        }
```

(`AppDelegate` is not @MainActor; `applicationDidFinishLaunching` runs on the main thread, the Task hop satisfies the compiler.)

- [ ] **Step 3: Build, test, commit**

Run: `swift build -c debug 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .+ tests" | tail -1`
Expected: build succeeds, all tests pass.

```bash
git add VeloxClip/Views/PasteStackHUD.swift VeloxClip/App/VeloxClipApp.swift
git commit -m "feat: paste stack HUD panel with corner/custom positioning"
```

---

### Task 6: Staging UI in the overlay (⊕ button, badge, Space key)

**Files:**
- Modify: `VeloxClip/Views/ClipboardListView.swift`
- Modify: `VeloxClip/Views/MainView.swift`

- [ ] **Step 1: Row badge + stage button**

In `ClipboardListView`, observe the service and pass staging info to rows. Change the struct head:

```swift
struct ClipboardListView: View {
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var pasteStack = PasteStackService.shared
    @Binding var selectedItem: ClipboardItem?
    var items: [ClipboardItem]
    @Binding var scrollTarget: UUID?
```

In the `ForEach`, pass two new parameters:

```swift
                    ClipboardItemRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        stagedIndex: pasteStack.stagedIndex(of: item.id),
                        onSelect: {
                            selectedItem = item
                        },
                        onDoubleClick: {
                            WindowManager.shared.selectAndPaste(item)
                        },
                        onToggleStage: {
                            pasteStack.toggleStaged(item)
                        }
                    )
```

In `ClipboardItemRow`, add the properties (after `isSelected`):

```swift
    let stagedIndex: Int?
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onToggleStage: () -> Void

    @State private var isHovering = false
```

(replacing the old `onSelect`/`onDoubleClick` declarations). Then replace the row's trailing `Spacer()` with:

```swift
            Spacer()

            if let stagedIndex {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                    Text("\(stagedIndex + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .onTapGesture { onToggleStage() }
                .help("In paste queue — click to remove")
            } else if isHovering {
                Button(action: onToggleStage) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add to paste queue (Space)")
            }
```

And after `.contentShape(Rectangle())` add:

```swift
        .onHover { isHovering = $0 }
```

Note: the ⊕ button and badge sit ABOVE the row's simultaneous tap gestures; `Button`/`onTapGesture` win over the row-level `TapGesture`, so tapping ⊕ doesn't also select/paste — verify this manually in Step 3.

- [ ] **Step 2: Space key staging in MainView**

In `MainView`, after the `.onKeyPress(.tab)` modifier, add:

```swift
            .onKeyPress(.space) {
                // Space stages only while the query is empty — otherwise it
                // must keep typing spaces into the search field
                guard searchText.isEmpty, let item = selectedItem else { return .ignored }
                PasteStackService.shared.toggleStaged(item)
                return .handled
            }
```

- [ ] **Step 3: Build + manual check**

Run: `swift build -c debug 2>&1 | tail -3`
Expected: build succeeds.

Manual (launch the debug build): open overlay, hover a row → ⊕ appears; click → ①  badge; Space on selected row toggles; with text in the search field Space types a space.

- [ ] **Step 4: Commit**

```bash
git add VeloxClip/Views/ClipboardListView.swift VeloxClip/Views/MainView.swift
git commit -m "feat: stage items into paste queue via hover button and Space key"
```

---

### Task 7: Menu-bar progress when HUD is disabled

**Files:**
- Modify: `VeloxClip/App/VeloxClipApp.swift`

- [ ] **Step 1: Dynamic MenuBarExtra label**

Replace the `MenuBarExtra("Velox Clip", systemImage: "paperclip.circle.fill") {` line and its closing brace structure with the label-closure form:

```swift
        MenuBarExtra {
            Button("Show Clipboard") {
                WindowManager.shared.toggleWindow()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Paste Image") {
                PasteImageService.shared.showPasteImage()
            }

            Divider()

            Button("Preferences...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Velox Clip") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            MenuBarLabel()
        }
```

Add at the bottom of the file:

```swift
// Shows paste-stack progress in the menu bar when the HUD is disabled,
// so the queue is never completely invisible
struct MenuBarLabel: View {
    @ObservedObject var stack = PasteStackService.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        if stack.phase != .idle && !settings.showPasteStackHUD {
            Image(systemName: "list.number")
            Text("\(min(stack.cursor + 1, stack.queue.count))/\(stack.queue.count)")
        } else {
            Image(systemName: "paperclip.circle.fill")
        }
    }
}
```

- [ ] **Step 2: Build, test, commit**

Run: `swift build -c debug 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .+ tests" | tail -1`
Expected: build succeeds, all tests pass.

```bash
git add VeloxClip/App/VeloxClipApp.swift
git commit -m "feat: menu-bar paste stack progress when HUD is off"
```

---

### Task 8: Docs, full verification, manual test pass

**Files:**
- Modify: `CLAUDE.md` (Services section)

- [ ] **Step 1: Document the service in CLAUDE.md**

In the `**Services/**` list in `CLAUDE.md`, add:

```markdown
- `PasteStackService` — sequential paste queue (Paste Stack): stage items in the overlay, each observed Cmd+V pastes the next; passive global key monitor + pre-write, never intercepts events. HUD in `Views/PasteStackHUD.swift`.
```

- [ ] **Step 2: Full build + tests**

Run: `swift build -c release --product VeloxClip 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .+ tests" | tail -1`
Expected: release build succeeds, all tests pass.

- [ ] **Step 3: Manual test checklist (launch the app)**

1. Overlay → stage 3 text items (⊕/Space) → badges ①②③ → ESC closes overlay → HUD appears bottom-right.
2. In TextEdit press Cmd+V three times into different lines → items paste in order, HUD advances 1/3 → 2/3 → 3/3 → "✓ Done" → HUD fades, clipboard restored to pre-stack content.
3. Mid-queue copy something in another app → HUD pauses → Cmd+V pastes the new copy → HUD ▶ resumes the queue.
4. Drag HUD → Settings shows "Custom (dragged)"; pick "Bottom Left" → next queue shows there.
5. Settings → HUD off → start a queue → menu bar shows `1/3` progress.
6. Stage 1 item + Enter-paste a different item → single paste lands first, then stack starts with the staged item.
7. Stage an image item → Cmd+V pastes the image into Preview/TextEdit.

- [ ] **Step 4: Commit + push**

```bash
git add CLAUDE.md
git commit -m "feat: paste stack — docs + final verification"
git push
```
