# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VeloxClip is a native macOS clipboard manager (macOS 14.0+) written in Swift 6.0 with SwiftUI. It runs as a menu bar app with a floating overlay window.

## Build & Test Commands

```bash
# Debug build
swift build -c debug

# Release build
swift build -c release --product VeloxClip

# Full app bundle + DMG packaging
./build_app.sh

# Run tests
swift test

# Run a single test
swift test --filter ClipboardStoreTests
swift test --filter DatabaseManagerMigrationTests
```

## Architecture

### Data Flow

```
macOS Pasteboard
  → ClipboardMonitor (polls every 0.5s)
  → ClipboardItem (type detection: text, image, RTF, file, color)
  → ClipboardStore (@MainActor — dedup, favorites, history limit)
  → DatabaseManager (@actor — async SQLite, thread-safe)
  → ~/Library/Application Support/VeloxClip/veloxclip.db
```

### Key Layers

**App/** — Entry point and window management. `VeloxClipApp.swift` handles menu bar setup and single-instance enforcement. `WindowManager.swift` manages the overlay window lifecycle.

**Models/** — Core state:
- `ClipboardStore` — @MainActor central state container; owns the items array, favorites, deduplication (5s window), and enforces history limit (only non-favorites count toward the limit)
- `DatabaseManager` — @actor async SQLite wrapper; all DB reads/writes are async and must be awaited
- `AppSettings` — @MainActor settings model; changes propagate to DB via `didSet`

**Services/** — Background work:
- `ClipboardMonitor` — pasteboard polling loop
- `AIService` — Apple Vision OCR + NaturalLanguage sentence embeddings with actor-based cache (200 item max)
- `ShortcutManager` — global keyboard shortcut registration
- `ContentDetectionService` — auto-tags items (json, table, url, code, markdown, datetime, etc.)
- `ScreenshotEditor/` — full annotation tool with pen, arrow, shapes, mosaic, undo/redo

**Views/** — SwiftUI UI:
- `MainView` — search list + hybrid search (keyword immediate + semantic 300ms debounce, combined scoring: keyword=0.9 weight)
- `PreviewView` — detail pane with tag editing and type-specific preview routing
- `PreviewComponents/` — specialized previews for each content type (code with syntax highlighting, JSON, table, URL+QR, color, datetime, image+OCR, markdown)
- `DesignSystem.swift` — design tokens and colors; use these for any new UI

### Concurrency Model

Swift 6 strict concurrency is enabled. Key patterns:
- `ClipboardStore` and `AppSettings` are `@MainActor` — access from background requires `await MainActor.run { }`
- `DatabaseManager` is an `@actor` — all calls must be `await`ed
- `AIService` uses an internal `@actor EmbeddingCache` for thread-safe caching
- Tests use `@MainActor` and `async/await` throughout

### Settings & Storage

- App settings: persisted to `app_settings` table in SQLite (key/value pairs)
- Default shortcuts: Cmd+Shift+V (show history), F1 (screenshot), F3 (paste image), Cmd+, (preferences)
- Database migration handles legacy schemas from prior "Velox"/"Velo" versions

### External Dependencies (Package.swift)

- `SQLite.swift` — SQLite ORM
- `swift-markdown-ui` — Markdown rendering in `MarkdownPreviewView`
- Apple frameworks: Vision (OCR), NaturalLanguage (embeddings), AppKit (pasteboard/shortcuts), ServiceManagement (launch at login)
