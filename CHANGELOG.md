# Changelog

All notable changes to **Velox Clip** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.17] - 2026-05-07

### Highlights / 亮点

- 🍔 *Settings → General* 新增 **Show Menu Bar Icon** 开关,可隐藏菜单栏图标 / New **Show Menu Bar Icon** toggle in *Settings → General* lets you hide the menu bar icon.
- 🔁 隐藏后双击应用图标会重新打开 Preferences,不会让用户失去入口 / When hidden, re-launching the app re-opens Preferences so you never lose access.
- ⌨️ 全局快捷键(`⌘⇧V` / `F1` / `F3`)即便图标隐藏也照常工作 / Global shortcuts (`⌘⇧V` / `F1` / `F3`) keep working even when the icon is hidden.
- 🛠️ 改用标准 SwiftUI `Settings` 场景,Preferences 行为更符合 macOS 习惯 / Switched to the standard SwiftUI `Settings` scene for more idiomatic macOS Preferences behavior.
- 🤖 首次启用 GitHub Actions 自动发版,tag push 即构建 .dmg 并发布(支持 fork) / First release to ship via GitHub Actions automation — tag push builds the `.dmg` and publishes the release (fork-aware).

### Added 新增

- `AppSettings.showMenuBarIcon` 持久化字段,默认 `true`,通过 SQLite 设置表保存 / Persisted `AppSettings.showMenuBarIcon` field (default `true`) stored in the SQLite settings table.
- 跨进程通知 `com.antigravity.veloxclip.openSettings` —— 二次启动时已运行实例会自动打开 Preferences / Cross-process distributed notification `com.antigravity.veloxclip.openSettings` so a duplicate launch tells the running instance to open Preferences.
- 冷启动兜底:若图标已隐藏,启动后自动打开 Preferences,确保用户随时能调整设置或退出 / Cold-start fallback: if the icon is hidden, Preferences opens automatically on launch so you can always re-enable it or quit.
- `AppSettings.isLoaded` 信号 —— 冷启动兜底基于真实加载完成事件而非固定 sleep / `AppSettings.isLoaded` signal lets the cold-start fallback wait on real load completion instead of a blind sleep.
- GitHub Actions release workflow + `scripts/build-release-notes.mjs`(Node 内置 test runner,9 个单测) / GitHub Actions release workflow plus `scripts/build-release-notes.mjs` (9 self-tests using Node's built-in runner).

### Changed 改进

- `WindowGroup(id: "settings")` 替换为 SwiftUI `Settings { }` 场景,菜单的 *Preferences…* 改用系统选择器 `showSettingsWindow:` / Replaced `WindowGroup(id: "settings")` with the standard SwiftUI `Settings { }` scene; the menu's *Preferences…* now uses the system `showSettingsWindow:` selector.
- `MenuBarExtra` 接受 `isInserted: $settings.showMenuBarIcon`,切换设置即时反映 / `MenuBarExtra` now binds `isInserted: $settings.showMenuBarIcon` for live show/hide.
- 设置项标签使用标题大小写并统一 *Velox Clip* 品牌写法,与 macOS HIG 保持一致 / Toggle label uses title case and the *Velox Clip* brand spelling, matching macOS HIG.
- `Info.plist` `CFBundleShortVersionString` 终于跟随 git tag(此前停在 `1.1`),由 CI 注入 `VERSION` 环境变量 / `Info.plist` `CFBundleShortVersionString` finally tracks the git tag (was stuck at `1.1`); injected via `VERSION` env in CI.
- CI runner 固定为 `macos-15` + Xcode 16(Swift 6) / Pinned CI runner to `macos-15` + Xcode 16 (Swift 6).

### Fixed 修复

- 修复 `DistributedNotificationCenter` 观察者闭包在 Swift 6 严格并发下访问 `NSApp` 引发的 main-actor 隔离告警 / Fixed Swift 6 strict-concurrency warnings when the `DistributedNotificationCenter` observer touched `NSApp` from a non-isolated closure (now hops to `@MainActor`).

### Internal 内部

- 设计文档与实现计划归档至 `docs/superpowers/specs/` 与 `docs/superpowers/plans/` / Design and implementation plan archived under `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## [1.1.16] - 2026-05-07 — superseded

未发布。在 fork CI 上因 `macos-14` runner 缺 Swift 6 而构建失败,被 v1.1.17 替代,内容已合并 /
Unreleased — CI build failed on `macos-14` (Swift 5.10) and was superseded by v1.1.17, which folds in the same content plus the runner fix.

[1.1.17]: https://github.com/Karl-Dai/VeloxClip/releases/tag/v1.1.17
