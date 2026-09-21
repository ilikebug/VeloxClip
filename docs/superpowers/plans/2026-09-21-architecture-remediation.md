# VeloxClip Architecture Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the three startup-race correctness bugs, invert the two upward dependencies, fix the persistence layer's index/blob/migration defects, split `Models/` into honest layers, remove singleton coupling from the view tree, and put CI + packaging gates in front of all of it.

**Architecture:** Work proceeds guardrails-first (nothing is safe to refactor until CI runs the 192 existing tests), then correctness, then persistence, then layering, then the directory split and de-singletonisation, then view performance. Each phase leaves the app building and all tests green.

**Tech Stack:** Swift 6.0 strict concurrency, SwiftUI, AppKit, SQLite.swift, XCTest, GitHub Actions (macos-14).

**Spec:** The architecture review in this session's conversation (four-reviewer fan-out, findings verified against source by the parent agent).

## Global Constraints

- Swift tools version 6.0; `.macOS(.v14)` platform floor. Strict concurrency must stay clean — no new `@unchecked Sendable`, no new `nonisolated(unsafe)`.
- `swift build -c debug` and `swift test` must pass at the end of EVERY task. 192 tests is the current baseline; the count may only go up.
- Never break the documented persistence invariants: list queries do not fetch the `data` blob; `DatabaseManager` exposes only narrow setters (no full-row update); dedup keys on `dataHash`; `lastUsedAt` moves items to top and `createdAt` is never rewritten; ordering is `COALESCE(lastUsedAt, createdAt) DESC`.
- Existing behaviour-preserving refactors must not change user-visible behaviour. Where a fix changes behaviour, it is called out explicitly in the task.
- Commit after each task with a conventional-commit message. Do not push until the whole plan is done and the user has reviewed.
- Keep the existing code comments that name the specific bug they prevent — they are load-bearing documentation. Carry them along when moving code.

---

## File Structure

**Created:**
- `.github/workflows/ci.yml` — build + test gate on macos-14
- `VeloxClip/Services/IngestionPipeline.swift` — serialised clipboard ingest
- `VeloxClip/Services/PasteboardService.swift` — single owner of `NSPasteboard.general`
- `VeloxClip/Services/AccessibilityPermission.swift` — dedup of the AX prompt policy
- `VeloxClip/Services/CacheRegistry.swift` — inverts Services→Views cache clearing
- `VeloxClip/Views/ErrorAlert.swift` — the `ViewModifier` half of ErrorHandler
- `VeloxClip/ViewModels/ClipboardSearchViewModel.swift` — search pipeline out of MainView
- `VeloxClip/Presentation/MainKeyRouter.swift` — typed keycode routing
- `VeloxClip/App/SingleInstanceGuard.swift` — flock-based instance claim
- `Tests/VeloxClipTests/{IngestionPipeline,PasteboardService,MainKeyRouter,ClipboardSearchViewModel,SchemaVersion}Tests.swift`

**Restructured:** `VeloxClip/Models/` splits into `VeloxClip/Domain/` (ClipboardStore, DatabaseManager, ClipboardItem, AppSettings), `VeloxClip/Presentation/` (RowPresentation, PreviewComponentPresentation, MenuBarDashboardPresentation, ColorFormatting, Command, ClipboardTypeFilter), `VeloxClip/Support/` (Localization, WebURL).

---

## Phase 0 — Guardrails

### Task 1: CI that actually builds and tests

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `.github/workflows/static.yml:37-39`

**Interfaces:**
- Produces: a required status check running `swift build -c debug` + `swift test` on macos-14.

- [ ] **Step 1: Create the CI workflow**

```yaml
name: CI

on:
  push:
    branches: ["main"]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Show toolchain
        run: swift --version
      - name: Build (debug)
        run: swift build -c debug
      - name: Test
        run: swift test
```

- [ ] **Step 2: Narrow the Pages upload**

The Pages job uploads `path: '.'` — the whole repo including `.build` when present. Restrict it to the actual site files. Replace the upload step's `path: '.'` with a staged directory built from `index.html`, `screenshots/`, `docs/`.

- [ ] **Step 3: Verify locally**

Run: `swift build -c debug && swift test`
Expected: Build complete, `Executed 192 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/static.yml
git commit -m "ci: build and test on macos-14; stop publishing the whole repo to Pages"
```

### Task 2: Packaging gate

**Files:**
- Modify: `build_app.sh:31-49`

**Interfaces:**
- Produces: `build_app.sh` that refuses to package when tests fail, when the build fails, or when only a stale binary exists.

- [ ] **Step 1: Run tests before building**

Insert before the release build: `swift test || { echo "[Error] Tests failed"; exit 1; }`

- [ ] **Step 2: Delete the stale binary and hard-fail on build error**

`rm -f "$ABS_BUILD_PATH/$BUILD_CONFIG/$EXECUTABLE_NAME"` before `swift build`, then replace the "executable exists, continuing" escape hatch (lines 37-49) with `[ $BUILD_STATUS -eq 0 ] || exit 1`.

- [ ] **Step 3: Verify**

Run: `./build_app.sh` — expect it to run tests, build, and produce `VeloxClip.dmg`.

- [ ] **Step 4: Commit**

```bash
git add build_app.sh
git commit -m "build: gate packaging on the test suite and a genuinely fresh binary"
```

### Task 3: Pin dependencies

**Files:**
- Modify: `.gitignore:14`
- Create (track): `Package.resolved`

- [ ] **Step 1:** Remove the `Package.resolved` line from `.gitignore`.
- [ ] **Step 2:** `git add -f Package.resolved`
- [ ] **Step 3:** Verify `git ls-files Package.resolved` prints the path.
- [ ] **Step 4: Commit**

```bash
git commit -m "build: track Package.resolved so dependency versions are reproducible"
```

---

## Phase 1 — Correctness: the three startup races

### Task 4: `load()` must merge, not replace

**Files:**
- Modify: `VeloxClip/Models/ClipboardStore.swift:364-381` (`load`), `:346-362` (`loadFavorites`)
- Test: `Tests/VeloxClipTests/ClipboardStoreTests.swift`

**Interfaces:**
- Produces: `ClipboardStore.load()` preserving items inserted while the DB read was in flight.

- [ ] **Step 1: Write the failing test**

```swift
func testLoadDoesNotDropItemsAddedWhileLoading() async throws {
    let url = TestSupport.makeDatabaseURL(name: "load-race")
    let db = DatabaseManager(databaseURL: url)
    let settings = AppSettings(dbManager: db)
    let persisted = ClipboardItem(type: "text", content: "from-db")
    try await db.insertClipboardItem(persisted)

    // shouldLoad: true starts the async read; insert before it lands
    let store = ClipboardStore(dbManager: db, settings: settings, shouldLoad: true)
    let live = ClipboardItem(type: "text", content: "copied-during-load")
    store.addItem(live)

    await TestSupport.waitUntil { store.items.contains { $0.id == persisted.id } }
    XCTAssertTrue(store.items.contains { $0.id == live.id },
                  "an item copied while the initial load was in flight must survive it")
    XCTAssertTrue(store.items.contains { $0.id == persisted.id })
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter testLoadDoesNotDropItemsAddedWhileLoading`
Expected: FAIL — `live` was overwritten by `self.items = loadedItems`.

- [ ] **Step 3: Implement the merge**

In `load()`, replace `self.items = loadedItems` with a merge that keeps any in-memory item the DB snapshot doesn't know about, then re-sorts by `lastUsedAt ?? createdAt` descending. Derive `favoriteItems` from the merged array, not from `loadedItems`.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: PASS, count ≥ 193.

- [ ] **Step 5: Commit**

```bash
git commit -am "fix(store): merge the initial load instead of replacing live items"
```

### Task 5: Single-instance claim before any work starts

**Files:**
- Create: `VeloxClip/App/SingleInstanceGuard.swift`
- Modify: `VeloxClip/App/VeloxClipApp.swift:6` (monitor `@StateObject`), `:283-337`
- Modify: `VeloxClip/Services/ClipboardMonitor.swift:10-13` (no polling from `init`)

**Interfaces:**
- Produces: `SingleInstanceGuard.claim() -> Bool` (flock on a lockfile beside the DB) and `ClipboardMonitor.start()`.

- [ ] **Step 1:** Add `SingleInstanceGuard` using `open(O_CREAT|O_RDWR)` + `flock(LOCK_EX|LOCK_NB)` on `~/Library/Application Support/VeloxClip/instance.lock`, holding the fd for process lifetime. Losing the lock means another instance owns it — activate it and exit.
- [ ] **Step 2:** Move the timer out of `ClipboardMonitor.init` into an explicit `func start()`. `init` only records `lastChangeCount`.
- [ ] **Step 3:** In `applicationWillFinishLaunching`, claim the lock; on failure activate the existing instance and terminate. Call `monitor.start()` from `applicationDidFinishLaunching` only after the claim succeeds.
- [ ] **Step 4:** `swift build -c debug && swift test`.
- [ ] **Step 5: Commit**

```bash
git commit -am "fix(app): claim a process lock before starting the clipboard monitor"
```

### Task 6: Serialise ingestion so history order matches copy order

**Files:**
- Create: `VeloxClip/Services/IngestionPipeline.swift`
- Modify: `VeloxClip/Services/ClipboardMonitor.swift:86-137`
- Test: `Tests/VeloxClipTests/IngestionPipelineTests.swift`

**Interfaces:**
- Produces: `actor IngestionPipeline { func submit(_ payload: PasteboardPayload) async }` processing FIFO, one ordered main-actor insert per item.

- [ ] **Step 1: Write the failing test** — submit a slow-to-decode image payload followed immediately by a text payload; assert the image lands in history ahead of the text.
- [ ] **Step 2:** Run it; expect FAIL (text wins today).
- [ ] **Step 3:** Implement the actor. The monitor's tick extracts the payload on the main actor (unchanged) and `await`s `pipeline.submit(payload)`; the pipeline does decode/normalise work in order and performs exactly one ordered insert per item.
- [ ] **Step 4:** `swift test`.
- [ ] **Step 5: Commit**

```bash
git commit -am "fix(monitor): serialise ingestion so history order matches copy order"
```

---

## Phase 2 — Persistence

### Task 7: Indices that match the actual sort keys

**Files:** Modify `VeloxClip/Models/DatabaseManager.swift:153-155`

- [ ] **Step 1:** Replace the `createdAt` index with an expression index on `COALESCE(lastUsedAt, createdAt) DESC`, and add `(isFavorite, COALESCE(favoritedAt, createdAt) DESC)`.
- [ ] **Step 2:** Verify with `EXPLAIN QUERY PLAN` in a scratch test that the list query no longer reports `USE TEMP B-TREE FOR ORDER BY`.
- [ ] **Step 3:** `swift test`; **Step 4:** commit.

### Task 8: Stop loading every embedding at launch

**Files:** Modify `VeloxClip/Models/DatabaseManager.swift:295-297`, add `fetchEmbeddings(ids:)`; update the semantic-search caller.

- [ ] **Step 1:** Write a test asserting `fetchAllClipboardItems()` returns items with `embedding == nil` (mirrors the existing `data == nil` invariant test).
- [ ] **Step 2:** Run, expect FAIL. **Step 3:** Drop `embedding` from `listColumns`; add a narrow `fetchEmbeddings(ids:) -> [UUID: Data]`. Point the semantic search at it.
- [ ] **Step 4:** `swift test`; **Step 5:** commit.

### Task 9: Atomic legacy-DB migration

**Files:** Modify `VeloxClip/Models/DatabaseManager.swift:70-98`

- [ ] **Step 1:** Move sidecars (`-wal`, `-shm`) BEFORE the main DB; on any throw, move everything back and leave the legacy path intact.
- [ ] **Step 2:** Replace `removeItem(at: legacyDB.deletingLastPathComponent())` with deletion of only the three files actually migrated, then `removeItem` on the directory only if empty.
- [ ] **Step 3:** Extend `DatabaseManagerMigrationTests` with a WAL-sidecar case. **Step 4:** `swift test`; **Step 5:** commit.

### Task 10: Backfill off the initialisation path

**Files:** Modify `VeloxClip/Models/DatabaseManager.swift:158-198`

- [ ] **Step 1:** Wrap the backfill loop in `try db.transaction { }` (one commit, not one fsync per row).
- [ ] **Step 2:** Move it out of `ensureInitialized` into `func runDeferredMaintenance() async`, kicked off by the app after the first successful load.
- [ ] **Step 3:** Keep `testLegacyBlobRowsGetDataHashBackfilled` passing by calling the new entry point. **Step 4:** `swift test`; **Step 5:** commit.

### Task 11: Schema versioning

**Files:** Modify `VeloxClip/Models/DatabaseManager.swift`; Test: `Tests/VeloxClipTests/SchemaVersionTests.swift`

- [ ] **Step 1:** Write a test that opening a DB whose `user_version` exceeds the binary's maximum throws rather than writing.
- [ ] **Step 2:** Run, expect FAIL. **Step 3:** Introduce `PRAGMA user_version` with an ordered migration list applied inside one transaction; refuse to open a newer schema. Fold the `dataHashBackfillDone` flag into the ledger.
- [ ] **Step 4:** `swift test`; **Step 5:** commit.

---

## Phase 3 — Layering

### Task 12: Invert the CacheManager→Views dependency

**Files:** Create `VeloxClip/Services/CacheRegistry.swift`; modify `VeloxClip/Services/CacheManager.swift:18-21`, `VeloxClip/Views/MarkdownRenderer.swift:35`, `VeloxClip/Views/PreviewComponents/JSONPreviewView.swift:34`

- [ ] **Step 1:** Add `@MainActor enum CacheRegistry { static func register(_ clear: @MainActor @escaping () -> Void); static func clearAll() }`.
- [ ] **Step 2:** Have the two view caches register themselves; `CacheManager.clearAllCaches()` calls `CacheRegistry.clearAll()` and names no view type.
- [ ] **Step 3:** Confirm `grep -n "MarkdownView\|JSONPreviewView" VeloxClip/Services/` is empty. **Step 4:** `swift test`; **Step 5:** commit.

### Task 13: Split ErrorHandler's view half out of Services

**Files:** Create `VeloxClip/Views/ErrorAlert.swift`; modify `VeloxClip/Services/ErrorHandler.swift:1-2,55-82`

- [ ] **Step 1:** Move `ErrorAlertModifier` and `extension View { errorAlert() }` to `Views/ErrorAlert.swift`.
- [ ] **Step 2:** Drop `import SwiftUI` from `ErrorHandler.swift` (Foundation + Combine only).
- [ ] **Step 3:** Route the user-visible Services failures through `ErrorHandler.shared.handle(_:)` — at minimum `ShortcutManager.swift:133` (a configured hotkey silently not registering), `TextCaptureService.swift:52`, `ScreenshotService.swift:52`, `ClipboardMonitor.swift:111,119` (a copy silently vanishing). Leave an explicit `// ignored because …` on any that stay silent.
- [ ] **Step 4:** `swift test`; **Step 5:** commit.

### Task 14: One owner for the pasteboard

**Files:** Create `VeloxClip/Services/PasteboardService.swift`; modify `ClipboardMonitor`, `PasteStackPasteboard`, `PasteImageService`, `ScreenshotService`, `TextCaptureService`, `ScreenshotEditorService`; Test: `Tests/VeloxClipTests/PasteboardServiceTests.swift`

**Interfaces:**
- Produces: `@MainActor final class PasteboardService` with `write(text:)`, `write(item:)`, `write(image:gated:)`, `read() -> PasteboardPayload`, `changeCount`, `capture()/restore()`. The three-step self-write protocol (clear+write → `recordSelfWrite` → `noteClipboardChange`) becomes internal to one call. `SystemPasteboardWriter` folds in as the production `PasteboardWriting` conformance.

- [ ] **Step 1:** Write tests against a uniquely-named `NSPasteboard` (the pattern in `PasteboardWritingTests.swift:7-9`) covering: a gated write records a self-write; the read type-priority ladder is file → text → rtf → png → tiff (one canonical order, replacing today's contradictory PNG-vs-TIFF preferences).
- [ ] **Step 2:** Run, expect FAIL. **Step 3:** Implement; migrate all six call sites. `TextCaptureService.swift:101-106` and `ScreenshotEditorService.swift:224-226` currently hand-roll or skip the protocol — both become one call.
- [ ] **Step 4:** Confirm `grep -rn "NSPasteboard.general" VeloxClip/` names only `PasteboardService.swift`. **Step 5:** `swift test`; **Step 6:** commit.

### Task 15: Deduplicate the Accessibility permission policy

**Files:** Create `VeloxClip/Services/AccessibilityPermission.swift`; modify `PasteStackService.swift:81-88,46`, `WindowManager.swift:329-336`

- [ ] **Step 1:** Mirror the shape of the existing, correct `ScreenCapturePermission`: `static var isGranted: Bool` + `@MainActor static func promptIfNeeded() -> Bool` owning the once-per-session flag.
- [ ] **Step 2:** Point both copies at it. Note this fixes a real defect: `WindowManager.swift:304` re-prompts on every failed paste because only the PasteStackService copy has the guard.
- [ ] **Step 3:** `swift test`; **Step 4:** commit.

### Task 16: Domain entity stops depending on presentation and AppKit

**Files:** Modify `VeloxClip/Models/ClipboardItem.swift:92,96-130`

- [ ] **Step 1:** Move `copyToPasteboard` into `PasteboardService` (Task 14's home). Preserve the decode-before-`clearContents` ordering and its comment — it prevents blanking the user's clipboard on an undecodable blob.
- [ ] **Step 2:** That removes both `import AppKit` and the `RowPresentation.filePaths` call from the entity. Update callers.
- [ ] **Step 3:** Confirm `ClipboardItem.swift` imports only Foundation + CryptoKit. **Step 4:** `swift test`; **Step 5:** commit.

---

## Phase 4 — Directory split

### Task 17: `Models/` becomes `Domain/` + `Presentation/` + `Support/`

**Files:** `git mv` across `VeloxClip/Models/*`

- [ ] **Step 1:** `Domain/`: ClipboardStore, DatabaseManager, ClipboardItem, AppSettings.
- [ ] **Step 2:** `Presentation/`: RowPresentation, PreviewComponentPresentation, MenuBarDashboardPresentation, ColorFormatting, Command, ClipboardTypeFilter. Drop the unused `import SwiftUI` from `Command.swift:1`.
- [ ] **Step 3:** `Support/`: Localization, WebURL.
- [ ] **Step 4:** Move `MenuBarDashboard` + `MenuBarLabel` (`VeloxClipApp.swift:33-280`) to `Views/MenuBarDashboardView.swift`, leaving the entry point as scene wiring + AppDelegate.
- [ ] **Step 5:** SwiftPM globs the target path, so no `Package.swift` change is needed. `swift build -c debug && swift test`.
- [ ] **Step 6: Commit**

```bash
git commit -am "refactor: split Models into Domain, Presentation and Support"
```

---

## Phase 5 — De-singleton and MainView extraction

### Task 18: Inject the stores instead of reaching for `.shared`

**Files:** Modify `VeloxClip/App/WindowManager.swift:167` (hosting root), then the view tree

- [ ] **Step 1:** Attach `.environmentObject(ClipboardStore.shared)` and `.environmentObject(AppSettings.shared)` at the `NSHostingController` root.
- [ ] **Step 2:** Convert view-layer `@ObservedObject … = X.shared` to `@EnvironmentObject`. Start with the highest-fanout offenders: `ClipboardListView.swift:41,121` and `JSONPreviewView.swift:256` — the recursive tree view installs one observer per JSON node today.
- [ ] **Step 3:** For `ClipboardItemRow`, pass `language: AppLanguage` as a plain `let` rather than observing all 11 `AppSettings` publishers. This is what makes dragging the paste-stack HUD stop invalidating every visible row.
- [ ] **Step 4:** `swift build -c debug && swift test`; **Step 5:** commit.

### Task 19: Search pipeline out of MainView

**Files:** Create `VeloxClip/ViewModels/ClipboardSearchViewModel.swift`; modify `MainView.swift:58-69,112-226`; Test: `Tests/VeloxClipTests/ClipboardSearchViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor final class ClipboardSearchViewModel: ObservableObject` owning `searchText`, `searchResults`, `isSearching`, the `FIFOCache`, and `updateSearchResults`/`publishSearchResults`/`performSemanticSearchAsync`, with the embedding source injected.

- [ ] **Step 1:** Write tests for the ranking rules that are untested today: keyword weight 0.9, the merge of keyword and semantic scores, tie-breaking.
- [ ] **Step 2:** Run, expect FAIL (types don't exist). **Step 3:** Extract, injecting the embedding provider so ranking is testable without a live `AIService`.
- [ ] **Step 4:** `swift test`; **Step 5:** commit.

### Task 20: A real key router

**Files:** Create `VeloxClip/Presentation/MainKeyRouter.swift`; modify `MainView.swift:382-509`; Test: extend `MainKeyRoutingPolicyTests.swift`

**Interfaces:**
- Produces: `enum MainKeyAction` and `static func route(keyCode:modifiers:isComposing:isEditingText:hasSelection:mode:) -> MainKeyAction`.

- [ ] **Step 1:** Write table-driven tests over the keycodes the 120-line switch handles today (126/125 arrows, 36/76 return, ⌘→ detail, ⌘⏎ stack, escape, …).
- [ ] **Step 2:** Run, expect FAIL. **Step 3:** Move the decision into the pure router; `handleKeyDown` shrinks to `switch MainKeyRouter.route(...)` plus the side effects. The existing four boolean helpers fold in.
- [ ] **Step 4:** `swift test`; **Step 5:** commit.

### Task 21: Typed command dispatch

**Files:** Modify `VeloxClip/Presentation/Command.swift:3-10`, `MainView.swift:600-642`

- [ ] **Step 1:** Replace `Command.id: String` with a `CommandKind` enum case. Update `CommandResolver` and `CommandResolverTests`.
- [ ] **Step 2:** `executeCommand`'s stringly-typed switch becomes an exhaustive switch the compiler checks.
- [ ] **Step 3:** `swift test`; **Step 4:** commit.

### Task 22: Invert shortcut registration

**Files:** Modify `VeloxClip/Services/ShortcutManager.swift:13-16,29-45,104-117`; Test: `Tests/VeloxClipTests/ShortcutManagerTests.swift`

- [ ] **Step 1:** Write a test that replacing a shortcut with an unparseable string leaves the existing registration intact (the documented regression at `:62-69`, currently untested).
- [ ] **Step 2:** Run, expect FAIL (can't construct the manager — it reads `AppSettings.shared` directly).
- [ ] **Step 3:** Change to `register(id:shortcut:action:)` with a `[UInt32: @MainActor () -> Void]` the Carbon callback looks up. The App layer wires shortcut → behaviour; Services stops naming `WindowManager`, `ScreenshotService`, `PasteImageService`, `TextCaptureService`. Pass shortcut strings in as parameters.
- [ ] **Step 4:** `swift test`; **Step 5:** commit.

---

## Phase 6 — View performance

### Task 23: Move expensive work out of `body`

**Files:** Modify `CodePreviewView.swift:15,64-71,180-226`, `URLPreviewView.swift:85-93,120-149`, `JSONPreviewView.swift:132-143,238-241,351-357`, `TablePreviewView.swift:44-45,87-129`, `TextSummaryView.swift:23-26,161-217`, `FilePreviewView.swift:140-158,300-339`

The correct pattern already exists in this directory — `ImagePreviewView.swift:145-177` does its work in `.task(id:)` inside `Task.detached` and publishes back via `MainActor.run`. Each fix below converts a sibling to match it.

- [ ] **Step 1:** `CodePreviewView` — move `detectLanguage()` (~250 full-document substring scans, currently synchronous in `.onAppear`) into `.task(id: code)`. Delete the `.onChange(of: detectedLanguage)` and `.onChange(of: fontSize)` cache wipes; both keys are already part of the cache key, and the wipe is what makes a cache described as persisting "between item switches" incapable of doing so. Precompute `[AttributedString]` into `@State` so `body` stops mutating a static cache.
- [ ] **Step 2:** `URLPreviewView` — cache the QR bitmap in `@State`; it is a pure function of the URL and is currently re-rendered through Core Image on every body pass. Delete the `isLoading` spinner at `:141-148` that guards work which does not exist.
- [ ] **Step 3:** `JSONPreviewView` — return the parsed object from the existing detached task instead of re-parsing on the main thread in `parseJSON()`; store `formattedLines: [String]` in `@State`; pre-sort dictionary keys at model-build time.
- [ ] **Step 4:** `TablePreviewView` — parse in `.task(id: content)`; precompute a lowercase joined search key per row; debounce the filter field.
- [ ] **Step 5:** `TextSummaryView` — compute word/char/line/paragraph counts and `allParagraphs` once in the existing `.task(id: text)` into a `TextStats` struct. Put the struct in `Presentation/` as a pure function and unit-test it.
- [ ] **Step 6:** `FilePreviewView` — wrap both loaders in `.task(id:)`; synchronous `attributesOfItem` on a stale network path currently blocks the overlay and its key monitor.
- [ ] **Step 7:** `swift test`; **Step 8:** commit each file group separately.

---

## Verification

- [ ] `swift build -c debug` clean, no new concurrency diagnostics.
- [ ] `swift test` — count ≥ 192 + the new tests, 0 failures.
- [ ] `./build_app.sh` produces a DMG with the Finder layout intact (UDZO format, `.DS_Store` ≈ 6 KB).
- [ ] `grep -rn "NSPasteboard.general" VeloxClip/` → only `PasteboardService.swift`.
- [ ] `grep -rn "MarkdownView\|JSONPreviewView" VeloxClip/Services/` → empty.
- [ ] `VeloxClip/Domain/ClipboardItem.swift` imports only Foundation + CryptoKit.
- [ ] Manual smoke: copy text, copy an image, copy files; all three appear in history in copy order. Toggle a favorite, clear history, stage a paste stack.
