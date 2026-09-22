# VeloxClip Optimization Plan (round 2)

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax. TDD throughout: failing test first, verified RED, then implement.

**Goal:** Close the remaining correctness, privacy, performance and testability gaps found in the two review passes.

**Spec:** The findings reported in-session after the architecture remediation merge.

## Global Constraints

- Swift 6.0 tools version, `.macOS(.v14)`. No new `@unchecked Sendable`, no new `nonisolated(unsafe)`.
- `swift build -c debug` and `swift test` green after EVERY task. Baseline: 271 tests, 2 skipped.
- Never break the persistence invariants: list queries omit `data` and `embedding`; narrow setters only; dedup on `dataHash`; `lastUsedAt` for move-to-top, never rewrite `createdAt`; ordering `COALESCE(lastUsedAt, createdAt) DESC`.
- Behaviour changes must be called out in the commit body.
- Conventional commits, one per task.

---

## Task 1: Semantic search sees whole documents

**Problem:** `AIService.generateEmbedding` truncates to 500 chars and uses the *truncated text* as the cache key. Ingestion embeds up to 2000 chars. So 500–2000 char items are half-represented (46 in the real DB), items sharing a 500-char opening collide on one cache entry, and >2000 char items get no embedding at all (2 in the real DB).

**Files:** `VeloxClip/Services/AIService.swift`, `VeloxClip/Services/ClipboardMonitor.swift`; Test: `Tests/VeloxClipTests/EmbeddingTruncationTests.swift`

- [ ] **Step 1:** Rewrite the test to assert the fixed behaviour: two documents sharing a 500-char opening must get different cache keys.
- [ ] **Step 2:** Run — RED.
- [ ] **Step 3:** Key the cache on a SHA256 of the full normalized text (`ClipboardItem.hash(of:)` already exists), not the truncated text. Raise the embed window to match ingestion's 2000-char bound so the two limits agree.
- [ ] **Step 4:** `swift test`. **Step 5:** commit.

## Task 2: Bounded history load

**Problem:** `fetchAllClipboardItems` has no LIMIT — the whole history is read into memory at launch.

**Files:** `VeloxClip/Domain/DatabaseManager.swift`, `VeloxClip/Domain/ClipboardStore.swift`; Test: `Tests/VeloxClipTests/DatabaseManagerTests.swift`

- [ ] **Step 1:** Test: inserting N+5 rows and fetching with `limit: N` returns N, newest first.
- [ ] **Step 2:** RED. **Step 3:** Add `limit:` (default nil = unbounded, so favorites/tests are unaffected); `ClipboardStore.load()` passes the history limit plus headroom for favorites.
- [ ] **Step 4:** `swift test`. **Step 5:** commit.

## Task 3: Sensitive-app blacklist becomes user-editable

**Problem:** `BlacklistManager` hardcodes 4 bundle IDs. Users of Bitwarden/Enpass/KeePassXC have their passwords recorded. Privacy gap with no UI.

**Files:** `VeloxClip/Services/BlacklistManager.swift`, `VeloxClip/Domain/AppSettings.swift`, `VeloxClip/Views/SettingsView.swift`, both `Localizable.strings`; Test: `Tests/VeloxClipTests/BlacklistManagerTests.swift`

- [ ] **Step 1:** Tests: defaults still ignored; a user-added ID is ignored; removing a user ID stops ignoring it; a removed *default* stays removed across a reload; matching is case-insensitive (bundle IDs are).
- [ ] **Step 2:** RED. **Step 3:** Persist the user's list in `app_settings`; `BlacklistManager` merges defaults + user additions minus user removals. Add a Privacy section to Settings with an app picker (`NSOpenPanel` limited to `/Applications`) and a removable list.
- [ ] **Step 4:** `swift test`. **Step 5:** commit.

## Task 4: Extract the screenshot compositor

**Problem:** `renderEditedImage`, `pixelatedPatch`, `applyMosaicEffect` are private methods on a 732-line `struct View`. Retina scaling, CG coordinate flipping and mosaic math — the parts that regress silently — are untestable, and the screenshot rework will need them.

**Files:** Create `VeloxClip/Services/ScreenshotEditor/AnnotationRenderer.swift`; modify `ScreenshotEditorView.swift`; Test: `Tests/VeloxClipTests/AnnotationRendererTests.swift`

- [ ] **Step 1:** Tests: output pixel size matches the source (not the on-screen point size); an empty element list returns an image equal in size to the input; a mosaic patch actually changes pixels in its rect and leaves pixels outside it untouched; coordinate flip puts a mark in the expected corner.
- [ ] **Step 2:** RED. **Step 3:** Move the three methods into `enum AnnotationRenderer` taking `(image:elements:)`, free of SwiftUI and `AppSettings`.
- [ ] **Step 4:** `swift test`. **Step 5:** commit.

## Task 5: Cover the untested services

**Problem:** `BlacklistManager` (covered by Task 3), `PreviewViewModel`, `CacheManager`/`CacheRegistry`, `ErrorHandler`, `EditorState` have zero tests. `EditorState` (339 lines) owns undo/redo — a real state machine.

**Files:** Create `Tests/VeloxClipTests/{EditorState,ErrorHandler,CacheRegistry}Tests.swift`

- [ ] **Step 1:** `EditorState`: undo pops the last element; redo restores it; a new element after undo clears the redo stack; clear empties both.
- [ ] **Step 2:** `ErrorHandler`: `handle` publishes, `clear` resets.
- [ ] **Step 3:** `CacheRegistry`: a registered handler runs on `clearAll`; multiple handlers all run.
- [ ] **Step 4:** `swift test`. **Step 5:** commit.

## Task 6: Raise the history ceiling

**Problem:** The limit picker offers 50/100/500/1000. The real DB sits exactly at 500/500 — every copy evicts one, which is what grew the file. With VACUUM in place a larger ceiling is now safe.

**Files:** `VeloxClip/Views/SettingsView.swift`

- [ ] **Step 1:** Add 2000 and 5000 options. **Step 2:** `swift test`. **Step 3:** commit.

## Verification

- [ ] `swift build -c debug` clean, no new concurrency diagnostics.
- [ ] `swift test` ≥ 271 + new tests, 0 failures.
- [ ] `./build_app.sh` produces a DMG (gate runs the suite).
- [ ] CI green on macos-26.
- [ ] `grep -rn "NSPasteboard.general" VeloxClip/` → only `PasteboardService.swift`.
- [ ] Manual: add an app to the blacklist, copy from it, confirm nothing is recorded.
