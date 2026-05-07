# Menu Bar Icon Visibility Toggle — Design

Date: 2026-05-07
Status: Approved (pending user review of this spec)

## Goal

Add a user-controlled setting that toggles the visibility of VeloxClip's menu bar icon. Hidden state must not strand the user — global shortcuts continue to work, and re-launching the app reopens Preferences.

## User-Facing Behavior

- A new toggle **Show menu bar icon** appears in *Settings → General*, directly under *Launch at Login*. Default: **on**.
- Help text: *"When hidden, re-launch VeloxClip to open Preferences."*
- Turning it **off**: menu bar icon disappears immediately. Global shortcuts (`cmd+shift+v`, `F1`, `F3`) remain functional.
- Turning it **on**: menu bar icon reappears immediately.
- **Re-opening Preferences when icon is hidden**: double-clicking VeloxClip.app (or launching via Spotlight/Dock) brings the running instance to the front and opens the Settings window.
- **Quitting when icon is hidden**: the user opens Preferences (per above), and uses the standard `cmd+Q` (SwiftUI provides this on the active app menu by default). No new in-window quit button.

## Architecture

### 1. Persisted setting

In `VeloxClip/Models/AppSettings.swift`:

- Add `@Published var showMenuBarIcon: Bool` with default `true`.
- Persist via the existing `DatabaseManager.setSetting/getSetting` pattern (key: `"showMenuBarIcon"`), mirroring `launchAtLogin`.
- Load in `loadSettings()` with the same `await MainActor.run` shape used by `launchAtLogin`.

### 2. MenuBarExtra binding

In `VeloxClip/App/VeloxClipApp.swift`:

- Inject `AppSettings.shared` into `VeloxClipApp` as `@ObservedObject` (or `@StateObject` if not yet held elsewhere at App scope).
- Replace the current `MenuBarExtra("Velox Clip", systemImage: "paperclip.circle.fill") { ... }` call with the `isInserted`-bound initializer:

  ```swift
  MenuBarExtra(
      "Velox Clip",
      systemImage: "paperclip.circle.fill",
      isInserted: $settings.showMenuBarIcon
  ) {
      // existing menu items unchanged
  }
  ```

  SwiftUI inserts/removes the menu item live as the binding flips.

### 3. Re-launch → open Preferences

The current second-instance detection in `AppDelegate.applicationDidFinishLaunching` already activates the running instance and quits. We extend it to also signal the running instance to open Settings.

Mechanism: **`DistributedNotificationCenter.default()`** (system-wide, no extra entitlements).

- Notification name: `"com.antigravity.veloxclip.openSettings"`.
- **Second (newly-launched) instance**, after `activateExistingInstance()` and before `terminate(nil)`:
  ```swift
  DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("com.antigravity.veloxclip.openSettings"),
      object: nil,
      userInfo: nil,
      deliverImmediately: true
  )
  ```
- **First (already-running) instance**, in `applicationDidFinishLaunching` (only on the path that does NOT terminate — i.e., when this instance is the surviving one):
  ```swift
  DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("com.antigravity.veloxclip.openSettings"),
      object: nil,
      queue: .main
  ) { _ in
      // open settings + activate
  }
  ```
  `AppDelegate` does not have access to `@Environment(\.openWindow)`, so we bridge via a small in-process event:
  - Introduce a tiny `@MainActor` singleton `AppEvents` exposing `let openSettings = PassthroughSubject<Void, Never>()`.
  - The App body attaches `.onReceive(AppEvents.shared.openSettings)` to a hidden `Color.clear` view inside the existing Settings `WindowGroup` scene host (or a top-level `Group` wrapping all scenes), and calls `openWindow(id: "settings")` plus `NSApp.activate(ignoringOtherApps: true)`.
  - The distributed-notification observer in `AppDelegate` calls `AppEvents.shared.openSettings.send()` on the main actor.

### 4. Cold-start fallback (icon hidden + app not running)

If `showMenuBarIcon == false` and the user starts the app from Finder/Dock/Spotlight when it is not already running, the user sees nothing without intervention.

Rule: in `applicationDidFinishLaunching`, after the "another instance" check passes, check `AppSettings.shared.showMenuBarIcon`. If false, programmatically open the Settings window and activate the app.

This keeps the feature symmetric: re-launch always reaches Settings, whether or not the app was already running.

## Failure Modes & Edge Cases

| Scenario | Behavior |
|---|---|
| Distributed notification fails to deliver | The second-instance `app.activate(...)` still front-fronts the existing instance's window if any is open. User sees the app come forward without Settings opening — degraded but not broken. |
| User disables icon, kills app via Activity Monitor, relaunches | Cold-start fallback opens Settings. |
| User disables icon, then disables/changes global shortcuts | Their explicit choice. Re-launching the app remains the recovery path. |
| Setting fails to persist (DB error) | Mirrors `launchAtLogin` failure mode — logged via `ErrorHandler.shared`, in-memory state retained for the session. |
| Toggle flipped while Settings window is open | `MenuBarExtra` updates live via binding; no restart needed. |

## Out of Scope

- No URL scheme registration. (Could be added later if other automation needs it.)
- No in-Settings "Quit VeloxClip" button. `cmd+Q` is sufficient.
- No alternative onboarding hints when icon is hidden (the help text on the toggle is the disclosure).

## Testing Plan

### Automated
- Extend existing `AppSettings` tests (if a test target already covers it) to assert:
  - Default value of `showMenuBarIcon` is `true`.
  - Round-trip persistence through `DatabaseManager`.

### Manual Verification Checklist
1. Fresh install → menu bar icon visible.
2. Toggle off → icon disappears immediately; `cmd+shift+v` still toggles main window; `F1` still triggers screenshot; `F3` still triggers paste-image.
3. With icon hidden, double-click VeloxClip.app in Finder → Settings window opens, app is activated.
4. With icon hidden, `cmd+Q` from Settings → app quits cleanly. Re-launch from Spotlight → Settings window opens automatically.
5. Toggle on while Settings is open → icon reappears immediately.
6. Reboot macOS, launch app → toggle state persists (read from DB).
7. Distributed-notification interaction: with icon visible and Settings closed, double-click app from Finder → Settings still opens (verifies the trigger path runs in both icon-visible and icon-hidden states).

## Files Touched

- `VeloxClip/Models/AppSettings.swift` — add property, persistence, default.
- `VeloxClip/App/VeloxClipApp.swift` — bind `MenuBarExtra(isInserted:)`, add distributed-notification observer/poster, cold-start fallback, internal "open settings" event plumbing.
- `VeloxClip/Views/SettingsView.swift` — add `Toggle("Show menu bar icon", ...)` to `GeneralSettingsView`'s first `Section`.

No new files are required. No third-party dependencies are added.
