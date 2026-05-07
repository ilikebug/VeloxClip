# Menu Bar Icon Visibility Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a user-controllable toggle that shows/hides the macOS menu bar icon, with a re-launch path that opens Preferences when the icon is hidden.

**Architecture:** A new `@Published var showMenuBarIcon` on `AppSettings` (DB-persisted) drives `MenuBarExtra(isInserted:)`. The existing `WindowGroup(id: "settings")` is replaced with a SwiftUI `Settings { SettingsView() }` scene so it can be opened reliably from anywhere via `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)` — even when no window or menu bar item is currently alive. Cross-instance signaling uses `DistributedNotificationCenter` so a second launch can ask the running instance to open Settings.

**Refinement vs. spec:** The spec proposed an `AppEvents` `PassthroughSubject` bridged from `AppDelegate` into a `WindowGroup`-hosted `.onReceive`. That breaks in exactly the failure mode the feature is designed for (icon hidden + Settings window closed): `WindowGroup` content is destroyed when the window is closed, so no subscriber exists to receive the event. Switching to the `Settings` scene + system selector preserves user-visible behavior, eliminates the need for `AppEvents`, and is the idiomatic macOS approach. No spec requirement is dropped.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSApplicationDelegate`, `DistributedNotificationCenter`, `NSApp.sendAction`), SQLite (existing `DatabaseManager`).

**Reference spec:** `docs/superpowers/specs/2026-05-07-menu-bar-icon-toggle-design.md`

**Project notes:**
- No `Tests/` directory exists; the `VeloxClipTests` target in `Package.swift` is a stub. Verification is via `swift build` for compilation and a manual checklist (Task 6) for behavior.
- Build command: `swift build -c debug` (use `build_app.sh` for full release packaging — required for Task 6 manual checks because realistic menu bar / bundle-id behavior depends on a proper `.app` bundle).
- Minimum macOS: 14 (per `Package.swift`); `MenuBarExtra(isInserted:)` requires macOS 13+, `showSettingsWindow:` selector requires macOS 14+. Both safe.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `VeloxClip/Models/AppSettings.swift` | Modify | Add `showMenuBarIcon` `@Published` property + DB load/save mirroring `launchAtLogin`. |
| `VeloxClip/Views/SettingsView.swift` | Modify | Add `Toggle("Show menu bar icon", ...)` to `GeneralSettingsView`'s first `Section`. |
| `VeloxClip/App/VeloxClipApp.swift` | Modify | (a) Replace `WindowGroup(id: "settings")` with `Settings { SettingsView() }`; (b) replace the menu's `openWindow(id: "settings")` with `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)`; (c) bind `MenuBarExtra(isInserted: $settings.showMenuBarIcon)`; (d) `AppDelegate` posts a distributed notification on the duplicate-instance path; (e) `AppDelegate` registers a distributed-notification observer that calls `showSettingsWindow:`; (f) cold-start fallback: when `showMenuBarIcon == false`, `AppDelegate` opens Settings on first launch. |

No new files. No new third-party dependencies. No `Info.plist` change.

---

### Task 1: Add `showMenuBarIcon` to `AppSettings`

**Files:**
- Modify: `VeloxClip/Models/AppSettings.swift`

- [ ] **Step 1: Add the `@Published` property**

In `VeloxClip/Models/AppSettings.swift`, locate the block that declares `@Published var launchAtLogin: Bool { ... }` (around lines 21–29). Immediately AFTER that block, insert:

```swift
    @Published var showMenuBarIcon: Bool {
        didSet {
            guard !isInitializing else { return }
            Task {
                try? await dbManager.setSetting(key: "showMenuBarIcon", value: String(showMenuBarIcon))
            }
        }
    }
```

- [ ] **Step 2: Initialize the default in `init()`**

In the same file, locate the `private init()` body (around lines 102–112). The line `self.launchAtLogin = false` is followed by `self.globalShortcut = "cmd+shift+v"`. Insert a new line BETWEEN those two:

```swift
        self.showMenuBarIcon = true
```

The block should now read:
```swift
        self.launchAtLogin = false
        self.showMenuBarIcon = true
        self.globalShortcut = "cmd+shift+v"
```

- [ ] **Step 3: Add load logic**

In `loadSettings()` (around lines 135–224), find the block that loads `launchAtLogin` (the one that ends with `try? await dbManager.setSetting(key: "launchAtLogin", value: "false")`). Insert this new block immediately AFTER it (BEFORE the `// Load globalShortcut` block):

```swift
        // Load showMenuBarIcon
        if let showMenuBarIconStr = await dbManager.getSetting(key: "showMenuBarIcon") {
            await MainActor.run {
                self.showMenuBarIcon = showMenuBarIconStr == "true"
            }
        } else {
            try? await dbManager.setSetting(key: "showMenuBarIcon", value: "true")
        }
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build -c debug 2>&1 | tail -20`
Expected: build succeeds (warnings OK).

- [ ] **Step 5: Commit**

```bash
git add VeloxClip/Models/AppSettings.swift
git commit -m "feat: persist showMenuBarIcon setting (default true)"
```

---

### Task 2: Add toggle to `GeneralSettingsView`

**Files:**
- Modify: `VeloxClip/Views/SettingsView.swift`

- [ ] **Step 1: Insert the toggle under "Launch at Login"**

In `VeloxClip/Views/SettingsView.swift`, locate the first `Section { ... }` inside `GeneralSettingsView.body` (around lines 60–71). It currently ends with:

```swift
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .help("Automatically start Velox Clip when you log in")
            }
```

Add a new toggle directly AFTER `Launch at Login`, INSIDE the same `Section`. The block should become:

```swift
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .help("Automatically start Velox Clip when you log in")

                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    .help("When hidden, re-launch VeloxClip to open Preferences.")
            }
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build -c debug 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add VeloxClip/Views/SettingsView.swift
git commit -m "feat(ui): add Show menu bar icon toggle in General settings"
```

---

### Task 3: Switch to `Settings` scene and bind `MenuBarExtra(isInserted:)`

**Files:**
- Modify: `VeloxClip/App/VeloxClipApp.swift`

- [ ] **Step 1: Add `AppSettings` `@StateObject` to the App struct**

In `VeloxClip/App/VeloxClipApp.swift`, locate the `VeloxClipApp` struct body (lines 4–9). It currently reads:

```swift
struct VeloxClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = ClipboardMonitor()

    @Environment(\.openWindow) var openWindow
```

Replace with (note: `@Environment(\.openWindow)` is removed — we no longer need it):

```swift
struct VeloxClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = ClipboardMonitor()
    @StateObject private var settings = AppSettings.shared
```

- [ ] **Step 2: Replace `WindowGroup(id: "settings")` with `Settings`**

The current Settings scene block (around lines 12–16) reads:

```swift
        // No WindowGroup for main app, but we need one for Settings
        WindowGroup(id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 350)
```

Replace with:

```swift
        // Standard Preferences scene — opens via the system "showSettingsWindow:" selector
        // from anywhere (menu, AppDelegate, distributed-notification handler).
        Settings {
            SettingsView()
        }
```

(The `Settings` scene handles its own sizing from the `SettingsView`'s internal `.frame(width: 500, height: 350)`, so the explicit modifiers are no longer required.)

- [ ] **Step 3: Bind `MenuBarExtra(isInserted:)`**

The current line (around line 18):

```swift
        MenuBarExtra("Velox Clip", systemImage: "paperclip.circle.fill") {
```

Replace with:

```swift
        MenuBarExtra(
            "Velox Clip",
            systemImage: "paperclip.circle.fill",
            isInserted: $settings.showMenuBarIcon
        ) {
```

(The closing `}` and inner buttons remain unchanged — Step 4 below updates one button.)

- [ ] **Step 4: Update the "Preferences..." menu button to use the system selector**

The current Preferences button (around lines 30–34) reads:

```swift
            Button("Preferences...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
```

Replace with:

```swift
            Button("Preferences...") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
```

- [ ] **Step 5: Verify it compiles**

Run: `swift build -c debug 2>&1 | tail -20`
Expected: build succeeds. There may be an "unused" warning if `monitor` was already unused (pre-existing); ignore.

- [ ] **Step 6: Commit**

```bash
git add VeloxClip/App/VeloxClipApp.swift
git commit -m "feat: use Settings scene and bind MenuBarExtra to showMenuBarIcon"
```

---

### Task 4: `AppDelegate` — post distributed notification on duplicate launch

**Files:**
- Modify: `VeloxClip/App/VeloxClipApp.swift`

- [ ] **Step 1: Define a notification name constant**

At the top of `VeloxClipApp.swift`, BELOW the `import SwiftUI` line and ABOVE the `@main struct VeloxClipApp` declaration, insert:

```swift
extension Notification.Name {
    static let veloxClipOpenSettings = Notification.Name("com.antigravity.veloxclip.openSettings")
}
```

- [ ] **Step 2: Post the notification in the duplicate-instance path**

In `AppDelegate.applicationDidFinishLaunching` (around lines 47–61), the current duplicate-instance handling is:

```swift
        // Check if another instance is already running
        if isAnotherInstanceRunning() {
            print("⚠️ Another instance of VeloxClip is already running. Activating it and quitting this instance.")
            activateExistingInstance()
            NSApplication.shared.terminate(nil)
            return
        }
```

Replace with:

```swift
        // Check if another instance is already running
        if isAnotherInstanceRunning() {
            print("⚠️ Another instance of VeloxClip is already running. Activating it and quitting this instance.")
            activateExistingInstance()
            DistributedNotificationCenter.default().postNotificationName(
                .veloxClipOpenSettings,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApplication.shared.terminate(nil)
            return
        }
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build -c debug 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add VeloxClip/App/VeloxClipApp.swift
git commit -m "feat: signal running instance to open Settings on duplicate launch"
```

---

### Task 5: `AppDelegate` — observer + cold-start fallback

**Files:**
- Modify: `VeloxClip/App/VeloxClipApp.swift`

- [ ] **Step 1: Register the distributed-notification observer and cold-start fallback**

In `AppDelegate.applicationDidFinishLaunching`, the surviving-instance path currently ends with:

```swift
        // Register all global shortcuts
        ShortcutManager.shared.registerAllShortcuts()

        // Note: Window will be shown when user presses the shortcut or clicks menu item
        // Removed auto-show on launch to avoid interrupting user workflow
    }
```

Replace it with:

```swift
        // Register all global shortcuts
        ShortcutManager.shared.registerAllShortcuts()

        // Listen for "open settings" requests from a duplicate launch attempt.
        DistributedNotificationCenter.default().addObserver(
            forName: .veloxClipOpenSettings,
            object: nil,
            queue: .main
        ) { _ in
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        // Cold-start fallback: if the menu bar icon is hidden, the user has no visible
        // entry point. Open Settings automatically so they can re-enable it or quit.
        Task { @MainActor in
            // Wait briefly so AppSettings has loaded its persisted value from disk.
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            if !AppSettings.shared.showMenuBarIcon {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }

        // Note: Main window will be shown when user presses the shortcut or clicks the menu item.
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build -c debug 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add VeloxClip/App/VeloxClipApp.swift
git commit -m "feat: open Settings on duplicate-launch signal and on cold start when icon hidden"
```

---

### Task 6: Manual verification

**Files:**
- None modified. Execution-and-observation only.

This project has no automated UI tests. Verify the feature against the spec's manual checklist using a real `.app` bundle (menu bar / bundle-id-matching behaviors require it).

- [ ] **Step 1: Build a release `.app` bundle**

Run: `./build_app.sh`
Expected: the script completes and prints the path to `VeloxClip.app`. If it fails, inspect `build_log.txt` and resolve build errors before proceeding.

- [ ] **Step 2: Walk the spec's Manual Verification Checklist**

Reference: `docs/superpowers/specs/2026-05-07-menu-bar-icon-toggle-design.md` § Testing Plan → Manual Verification Checklist.

For each item below, perform the action, observe, and tick if it matches the expected behavior. If it does NOT match, stop and write a fix as a new commit.

  1. **Fresh-state check.** With no prior `showMenuBarIcon` value persisted (you can test by deleting the app's SQLite DB if needed) → launch app → menu bar icon visible.
  2. **Toggle off.** Open *Settings → General*, switch off **Show menu bar icon** → icon disappears immediately. Press `cmd+shift+v` → main clipboard window toggles. Press `F1` → screenshot mode triggers. Press `F3` → paste-image mode triggers.
  3. **Re-launch with icon hidden (app already running).** With icon still hidden, double-click `VeloxClip.app` from Finder → the existing instance brings the Settings window to the front and activates the app.
  4. **Cold-start with icon hidden.** With icon hidden and Settings window focused, press `cmd+Q` to quit. Then re-launch from Spotlight → Settings window opens automatically (cold-start fallback).
  5. **Toggle on.** With Settings still open, switch **Show menu bar icon** back on → icon reappears immediately.
  6. **Persistence.** Quit the app, reboot macOS, launch app → toggle state matches what it was before the reboot.
  7. **Re-launch with icon visible.** With icon visible and Settings closed, double-click `VeloxClip.app` from Finder → Settings still opens (verifies the duplicate-launch signal path runs in both icon states).

- [ ] **Step 3: Record results**

If all items pass, note completion in the commit log of the merge / PR description for this feature. No additional commit is required.

If any item fails, fix and commit:

```bash
git commit -m "fix(menu-bar-toggle): <what broke>; fixes manual checklist item N"
```

Then re-run the failed item.

---

## Self-Review Notes

- **Spec coverage:**
  - "Show menu bar icon" toggle in General → Task 2.
  - Help text → Task 2.
  - `MenuBarExtra(isInserted:)` binding → Task 3 Step 3.
  - DB persistence (key `"showMenuBarIcon"`, default `true`) → Task 1.
  - Duplicate-launch → Settings open via `DistributedNotificationCenter` → Tasks 4 + 5.
  - AppDelegate ↔ Settings-window bridge → Task 3 Step 2 (`Settings` scene) + Task 5 Step 1 (`showSettingsWindow:` selector). Replaces the spec's `AppEvents` design with a more reliable mechanism; documented in the **Refinement vs. spec** section above.
  - Cold-start fallback when `showMenuBarIcon == false` → Task 5 Step 1.
  - Quit via `cmd+Q` (no new in-window button) → no code task; covered by manual checklist item 4.
  - Manual verification checklist → Task 6.
- **Placeholders:** none. All code is shown in full.
- **Type consistency:** `showMenuBarIcon` (`Bool`), DB key `"showMenuBarIcon"`, notification name `.veloxClipOpenSettings` (string `"com.antigravity.veloxclip.openSettings"`), selector `Selector(("showSettingsWindow:"))` — used identically across Tasks 1, 3, 4, 5.
