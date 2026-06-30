# VeloxClip 界面套件还原 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按设计图《VeloxClip 界面套件》逐像素还原全部界面（去渐变、统一系统蓝 `#0A84FF`），并新增 ⌘K 命令面板。

**Architecture:** 先重建 `DesignSystem.swift` 为一套浅/深 token 层（替换全局紫靛渐变），随后逐屏改造视图以引用 token；最后新增一个上下文相关的 ⌘K 命令面板浮层，复用现有动作入口。

**Tech Stack:** Swift 6 / SwiftUI / AppKit；测试 `swift test`（XCTest）。设计图：`~/Desktop/VeloxClip 界面套件.html`，逐像素值用以下命令重新提取：
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --virtual-time-budget=9000 --dump-dom \
  "file:///Users/y.zhang/Desktop/VeloxClip%20%E7%95%8C%E9%9D%A2%E5%A5%97%E4%BB%B6.html" > /tmp/vc_rendered.html
```
然后在 `/tmp/vc_rendered.html` 中按可见文案 grep 出对应元素的内联样式取精确 px。

---

## 工作约定（每个 Task 通用）

- 分支：`feat/ui-kit-redesign`（已创建）。
- 仅使用 DesignSystem 基元，禁用系统默认控件与语义字体（项目惯例）。
- **每个 Task 的「验证」三件套：**
  1. `swift build -c debug` 编译通过；
  2. `swift test`（全量或相关 filter）保持全绿——**视图改造不得破坏既有模型/服务测试**；
  3. **用户手动运行 App、截图、与设计图对比** —— Claude 在此暂停，等用户确认后再进入下一个 Task。
- SwiftUI 纯视觉改动**没有可写的单元测试**；本计划只在有真实逻辑处（Task 1 的 token 取值、Task 7 的 "system" 外观、Task 8 的命令解析）写 XCTest。
- 提交粒度：每个 Task 完成且测试通过即 commit。

---

## File Structure

| 文件 | 责任 | Task |
|---|---|---|
| `VeloxClip/Views/DesignSystem.swift` | token 层（浅/深色值、字体、按钮/开关/滑块、DSKeyBadge）。删除 `primaryGradient`。 | 1 |
| `VeloxClip/Views/MainView.swift` | 主浮层：搜索栏、历史/收藏分段、类型 chip、底部操作栏 | 2 |
| `VeloxClip/Views/ClipboardListView.swift` | 列表行：选中态纯蓝、⌘N 键帽 | 2 |
| `VeloxClip/Views/EmptyStateView.swift`（新建） | 空态/无匹配/收藏空 | 3 |
| `VeloxClip/Views/PreviewView.swift` + `PreviewComponents/*` | 详情头部 + 五类预览 token 化 | 4 |
| `VeloxClip/Views/PasteStackHUD.swift` | HUD 三态 | 5 |
| `VeloxClip/Services/ScreenshotEditor/ScreenshotEditorView.swift` | 标注工具栏 token 化 | 6 |
| `VeloxClip/Views/SettingsView.swift` + `Models/AppSettings.swift` | 设置 + 跟随系统外观 | 7 |
| `VeloxClip/Views/CommandPaletteView.swift`（新建） + `Models/Command.swift`（新建） | ⌘K 命令面板 + 命令解析 | 8 |
| `Tests/VeloxClipTests/AppearanceTests.swift`（新建） | "system" 外观行为 | 7 |
| `Tests/VeloxClipTests/CommandResolverTests.swift`（新建） | 命令解析逻辑 | 8 |

---

## Task 1: 设计 Token 基础层

**Files:**
- Modify: `VeloxClip/Views/DesignSystem.swift`（替换 `primaryGradient`、新增 token/DSKeyBadge）
- Modify（迁移引用）: `VeloxClip/Views/MainView.swift`、`VeloxClip/Views/PreviewView.swift`、`VeloxClip/Views/PasteStackHUD.swift`、`VeloxClip/Services/ScreenshotEditor/ScreenshotEditorView.swift`

- [ ] **Step 1: 在 DesignSystem.swift 新增 token 入口（浅/深由 colorScheme 切换）**

在 `extension Color` 上方插入。颜色值即设计图根 CSS 变量；深色为推导值（见 spec §3）：

```swift
// MARK: - Design tokens (light = 设计图; dark = 推导)
//
// 设计图《VeloxClip 界面套件》全程无渐变，统一系统蓝 #0A84FF。
// 取值随当前 colorScheme 切换；强调色跟随系统（回退 #0A84FF）。
extension Color {
    static func ds(_ light: String, _ dark: String, _ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? dark : light)!
    }
}

struct DSColors {
    let scheme: ColorScheme
    // 强调色跟随系统：用 AppKit controlAccentColor，回退 #0A84FF
    var accent: Color { Color(nsColor: .controlAccentColor) }
    var accentSoft: Color { Color(.sRGB, red: 10/255, green: 132/255, blue: 1, opacity: scheme == .dark ? 0.22 : 0.14) }
    var text: Color   { .ds("#1d1d1f", "#f5f5f7", scheme) }
    var text2: Color  { .ds("#86868b", "#98989d", scheme) }
    var text3: Color  { .ds("#aeaeb2", "#636366", scheme) }
    var window: Color { .ds("#f4f3f1", "#1e1e1e", scheme) }
    var card: Color   { .ds("#ffffff", "#2c2c2e", scheme) }
    var panel: Color  { scheme == .dark ? Color(.sRGB, red: 40/255, green: 40/255, blue: 42/255, opacity: 0.80)
                                        : Color(.sRGB, red: 250/255, green: 250/255, blue: 249/255, opacity: 0.78) }
    func blackAlpha(_ a: Double, _ darkWhiteA: Double) -> Color {
        scheme == .dark ? Color.white.opacity(darkWhiteA) : Color.black.opacity(a)
    }
    var field: Color   { blackAlpha(0.055, 0.08) }
    var chip: Color    { blackAlpha(0.05, 0.07) }
    var key: Color     { blackAlpha(0.06, 0.10) }
    var divider: Color { blackAlpha(0.09, 0.12) }
    var hover: Color   { blackAlpha(0.045, 0.06) }
}

extension EnvironmentValues {
    var dsColors: DSColors { DSColors(scheme: self.colorScheme) }
}
```

> 注：SwiftUI 没有内建 `dsColors` 环境键，用计算属性即可——`@Environment(\.colorScheme)` 已存在；在视图里写 `@Environment(\.colorScheme) private var scheme` 再 `let c = DSColors(scheme: scheme)`。若 `EnvironmentValues` 扩展引发 KeyPath 报错，则删掉该 extension，视图内直接 `DSColors(scheme: scheme)`。

- [ ] **Step 2: 删除 primaryGradient，新增纯色 accent helper + 阴影 token**

将 `DesignSystem.primaryGradient`（第 5-9 行）整段删除，替换为：

```swift
struct DesignSystem {
    /// 面板投影：0 18px 50px rgba(0,0,0,.2)（深色 .5）
    static func panelShadow(_ scheme: ColorScheme) -> Color {
        .black.opacity(scheme == .dark ? 0.5 : 0.2)
    }
    static let backgroundBlur = VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
    struct Card: ViewModifier { /* 保留原实现 */
        func body(content: Content) -> some View {
            content.padding().background(Color.white.opacity(0.12)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}
```

- [ ] **Step 3: DSButtonStyle / DSSwitch / DSSlider 去渐变**

把三处 `DesignSystem.primaryGradient` 改为系统强调色：
- `DSButtonStyle.fill` 的 `.prominent` 分支：`return AnyShapeStyle(Color(nsColor: .controlAccentColor))`
- `DSSwitchToggleStyle`：`configuration.isOn ? AnyShapeStyle(Color(nsColor: .controlAccentColor)) : ...`
- `DSSlider`：填充 Capsule `.fill(Color(nsColor: .controlAccentColor))`

- [ ] **Step 4: 新增 DSKeyBadge 组件**

在文件末尾 `extension Color` 之前插入。先从渲染 DOM 取键帽精确样式（`grep -A2 '⌘' /tmp/vc_rendered.html` 看 font-size/padding/radius），默认值：

```swift
// MARK: - Keyboard badge (⌘1 / ⏎ / space)
struct DSKeyBadge: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    var body: some View {
        let c = DSColors(scheme: scheme)
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(c.text2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(c.key))
    }
}
```

- [ ] **Step 5: 迁移 5 个文件的 primaryGradient 引用**

`grep -rln primaryGradient VeloxClip/` 应只剩 0 处（DesignSystem 自身已删）。逐个把 `MainView`/`PreviewView`/`PasteStackHUD`/`ScreenshotEditorView` 里的 `.foregroundStyle(DesignSystem.primaryGradient)` 等改为 `.foregroundStyle(Color(nsColor: .controlAccentColor))`（按各处语义；放大镜图标改 `c.text2`）。本步只求编译通过、不回归——精细布局留给各自 Task。

- [ ] **Step 6: 编译 + 测试**

Run: `swift build -c debug && swift test`
Expected: build 成功；既有测试全绿。

- [ ] **Step 7: 确认无残留渐变**

Run: `grep -rn "primaryGradient\|LinearGradient" VeloxClip/`
Expected: 0 hits（或仅注释）。

- [ ] **Step 8: 用户手测暂停**，确认整体观感转为纯平系统蓝、无明显回归。

- [ ] **Step 9: Commit**

```bash
git add VeloxClip/Views/DesignSystem.swift VeloxClip/Views/MainView.swift VeloxClip/Views/PreviewView.swift VeloxClip/Views/PasteStackHUD.swift VeloxClip/Services/ScreenshotEditor/ScreenshotEditorView.swift
git commit -m "refactor(ui): replace gradient with flat system-blue token layer + DSKeyBadge"
```

---

## Task 2: 主浮层 MainView + 列表行

**Files:**
- Modify: `VeloxClip/Views/MainView.swift`
- Modify: `VeloxClip/Views/ClipboardListView.swift`

精确像素：从 `/tmp/vc_rendered.html` grep `主浮层`/`历史`/`收藏`/`全部` 区域取搜索栏高度、chip padding、行高、键帽位置。

- [ ] **Step 1: 搜索栏紧凑化 + ⌘V 提示**

`MainView.body` 顶部 HStack（159-178 行）：放大镜改 `c.text2`、`size: 14`；TextField 去 `.rounded`，改 `.font(.system(size: 13))`；占位文案 `搜索剪贴…`；右侧用 `DSKeyBadge("⌘V")` 替换星形按钮区域内联提示。`padding(.horizontal, 14).padding(.vertical, 10)`。

- [ ] **Step 2: 历史/收藏分段标签替换星形 toggle**

删除 `favoriteToggleButton`（364-384 行）。新增分段控件（沿用 viewMode）：两段「历史 / 收藏」，选中段 `c.accentSoft` 底 + `c.accent` 字，未选 `c.text2`；放在列表列顶部、与类型 chip 同一行（左对齐分段，右对齐 chip）。

- [ ] **Step 3: 类型 chip 移到分段右侧并紧凑化**

改写 `typeFilterBar`（337-362 行）：去 `.rounded`、去 `maxWidth: .infinity` 等宽铺满；改为内容宽 chip，水平排列，选中 = `c.accent` 纯色 + 白字，未选 = `c.chip` 底 + `c.text2`，`padding(.horizontal,8).padding(.vertical,3)`，圆角 20（胶囊）。与 Step 2 分段放进同一 `HStack`。

- [ ] **Step 4: 底部操作栏（新增）**

在 `MainView.body` 最外层 VStack（156 行）末尾、`.frame(width:850,height:600)` 之前，新增分割线 + 操作栏：
```swift
Divider().overlay(c.divider)
HStack(spacing: 14) {
    actionHint("粘贴", "⏎"); actionHint("详情", nil)
    actionHint("入栈", "space"); actionHint("动作", "⌘K")
    Spacer()
    Text("\(displayItems.count) 条").font(.system(size: 11)).foregroundColor(c.text3)
}.padding(.horizontal, 14).padding(.vertical, 8)
```
`actionHint(_:_ key:)` 私有方法：文案 `c.text2` 11px + 可选 `DSKeyBadge(key)`。

- [ ] **Step 5: 列表选中态纯蓝 + ⌘N 键帽**

`ClipboardListView` 的 `ClipboardItemRow`（59-147 行）：
- 选中背景（126-129 行）改为 `isSelected ? c.accent : (isHovering ? c.hover : .clear)`；选中时标题/副标题/图标 = 白色。
- 右侧区域：选中行显示 `DSKeyBadge("⏎")`（白底变体——选中时用 `Color.white.opacity(0.2)` 底 + 白字）；非选中行若 `index < 9` 显示 `DSKeyBadge("⌘\(index+1)")`。需把行 index 传入：`ForEach(Array(items.enumerated()), id: \.element.id)`。
- 标题去 `.rounded`，改 `.font(.system(size: 13))`。

- [ ] **Step 6: ⌘1–9 触发粘贴对应行**

`MainView.body` 顶部 HStack 已有 `onKeyPress`。新增：
```swift
.onKeyPress { press in
    guard press.modifiers.contains(.command),
          let n = Int(press.characters), n >= 1, n <= 9,
          displayItems.indices.contains(n-1) else { return .ignored }
    WindowManager.shared.selectAndPaste(displayItems[n-1]); return .handled
}
```

- [ ] **Step 7: 编译 + 测试**

Run: `swift build -c debug && swift test`
Expected: 通过；`ClipboardTypeFilterTests` 全绿（typeFilter 行为未变）。

- [ ] **Step 8: 用户手测暂停**（对比设计图①：分段、chip、选中纯蓝、⌘N 键帽、底部栏）。

- [ ] **Step 9: Commit**
```bash
git add VeloxClip/Views/MainView.swift VeloxClip/Views/ClipboardListView.swift
git commit -m "feat(ui): main overlay tabs + type chips + solid-blue selection + action bar"
```

---

## Task 3: 空态 / 收藏态

**Files:**
- Create: `VeloxClip/Views/EmptyStateView.swift`
- Modify: `VeloxClip/Views/ClipboardListView.swift`（无 item 时渲染空态）

- [ ] **Step 1: 新建 EmptyStateView**
```swift
import SwiftUI
struct EmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundColor(c.text3)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(c.text2)
            Text(subtitle).font(.system(size: 11)).foregroundColor(c.text3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: 列表为空时渲染对应空态**

`ClipboardListView.body`：`if items.isEmpty { EmptyStateView(...) }` else List。文案分支由父级传入（搜索无结果 → 「无匹配 / 试别的词，或切到收藏」；历史空 → 「还没有剪贴记录 / 复制点什么，这里就会出现」）。新增 `var emptyKind: EmptyKind` 参数，从 `MainView` 依据 `searchText`/`viewMode` 传入。

- [ ] **Step 3: 编译 + 测试** `swift build -c debug && swift test` → 通过。
- [ ] **Step 4: 用户手测暂停**（清空/搜索无结果对比设计图②）。
- [ ] **Step 5: Commit** `git commit -am "feat(ui): styled empty & no-match states"`

---

## Task 4: 详情视图 PreviewView + PreviewComponents

**Files:**
- Modify: `VeloxClip/Views/PreviewView.swift`
- Modify: `VeloxClip/Views/PreviewComponents/{ColorPreviewView,URLPreviewView,ImagePreviewView,CodePreviewView,JSONPreviewView}.swift`

精确像素：grep `详情视图`/`颜色`/`链接`/`HEX`/`打开链接` 区段。

- [ ] **Step 1: 统一详情头部**

`PreviewView`：顶部 HStack = `‹`(返回，可隐藏) + 类型标题(13px semibold `c.text`) + Spacer + ★(收藏 toggle，选中 `c.accent`) + ✕(关闭)。下方标签 chip 行用 `c.chip` 底。去该文件内任何渐变。

- [ ] **Step 2: 颜色预览 token 化**

`ColorPreviewView`：大色块 + HEX/RGB/HSL 三行，每行 `c.field` 底、等宽值、右侧复制按钮（`dsButton(.secondary, small:true)`）。标签 chip「品牌色 / UI」。

- [ ] **Step 3: 链接预览**

`URLPreviewView`：QR 居中 + 「打开链接」`dsButton(.prominent)` + 「复制」`dsButton(.secondary)`。

- [ ] **Step 4: 图片 / 代码 / JSON**

`ImagePreviewView`：占位斜纹 + 尺寸标题 + 「图中文字」OCR 区（`c.card`）。`CodePreviewView`/`JSONPreviewView`：`c.card` 底 + 行号 `c.text3` + 等宽体；语法高亮色保持现有。

- [ ] **Step 5: 编译 + 测试** → 通过。
- [ ] **Step 6: 用户手测暂停**（五类预览对比设计图③）。
- [ ] **Step 7: Commit** `git commit -am "feat(ui): detail header + token-based previews"`

---

## Task 5: Paste Stack HUD 三态

**Files:**
- Modify: `VeloxClip/Views/PasteStackHUD.swift`

精确像素：grep `Paste Stack HUD`/`进行中`/`暂停`/`已暂停`/`已粘贴` 区段。

- [ ] **Step 1: 进行中态**：标题「Paste Stack」+ `n / m` + 行列表，当前项 `c.accent` 高亮 + ⏎ 键帽，已完成项灰勾。去渐变。
- [ ] **Step 2: 暂停态**：黄条「已暂停 — 你复制了新内容」（`Color.orange.opacity(0.15)` 底）+ 「继续」`dsButton(.prominent)` /「放弃」`dsButton(.secondary)`。
- [ ] **Step 3: 完成态**：`c.accent` 实心圆 + 白勾 + 「已粘贴 N 项 / 序列完成」+ 说明「位置可在设置中改 · 默认右下角」。
- [ ] **Step 4: 编译 + 测试** → 通过；`PasteStackServiceTests` 全绿。
- [ ] **Step 5: 用户手测暂停**（三态对比设计图④）。
- [ ] **Step 6: Commit** `git commit -am "feat(ui): Paste Stack HUD three-state restyle"`

---

## Task 6: 截图标注编辑器

**Files:**
- Modify: `VeloxClip/Services/ScreenshotEditor/ScreenshotEditorView.swift`

精确像素：grep `截图标注编辑器`/`标注` 区段（工具栏排布、颜色点尺寸）。

- [ ] **Step 1: 工具栏 token 化**：选择/笔/箭头/矩形/椭圆/文字/马赛克按钮，选中工具 `c.accentSoft` 底 + `c.accent` 图标；颜色点（红/蓝/黄/黑）；粗细分段；撤销/重做；「完成」`dsButton(.prominent)`。去渐变。
- [ ] **Step 2: 编译 + 测试** → 通过。
- [ ] **Step 3: 用户手测暂停**（F1 唤起对比设计图⑤）。
- [ ] **Step 4: Commit** `git commit -am "feat(ui): screenshot editor toolbar restyle"`

---

## Task 7: 设置 + 跟随系统外观

**Files:**
- Modify: `VeloxClip/Models/AppSettings.swift`
- Modify: `VeloxClip/Views/SettingsView.swift`
- Create: `Tests/VeloxClipTests/AppearanceTests.swift`

- [ ] **Step 1: 写失败测试 —— "system" 外观应清空 NSApp.appearance override**
```swift
import XCTest
@testable import VeloxClip
@MainActor final class AppearanceTests: XCTestCase {
    func testSystemAppearanceClearsOverride() {
        let s = AppSettings.shared
        s.appearance = "dark";  s.applyAppearance(); XCTAssertNotNil(NSApp.appearance)
        s.appearance = "system"; s.applyAppearance(); XCTAssertNil(NSApp.appearance)
    }
}
```
- [ ] **Step 2: 跑测试确认失败** `swift test --filter AppearanceTests` → FAIL（"system" 当前落到 aqua 分支，appearance 非 nil）。
- [ ] **Step 3: 实现 "system" 分支**

`AppSettings.applyAppearance()`（262-266 行）改为：
```swift
func applyAppearance() {
    switch appearance {
    case "dark":   NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    case "light":  NSApplication.shared.appearance = NSAppearance(named: .aqua)
    default:        NSApplication.shared.appearance = nil // system
    }
}
```
更新注释与默认值注释（"light"|"dark"|"system"）。
- [ ] **Step 4: 跑测试确认通过** `swift test --filter AppearanceTests` → PASS。
- [ ] **Step 5: SettingsView 外观区**：主题分段加入第三项「跟随系统」(`("system","跟随系统")`，113-117 行 options)；新增「强调色」行展示系统强调色圆点 `Color(nsColor:.controlAccentColor)` + 「跟随系统」说明（只读）。
- [ ] **Step 6: SettingsView 其余分区 token 化**：左侧分栏（外观/历史/Paste Stack/快捷键/高级）；历史上限分段 50/100/500/1000；开机启动/显示进度浮窗 DSSwitch；浮窗位置网格；快捷键 DSKeyBadge；清缓存/清历史（`dsButton(.destructive)`）。全部 DesignSystem 基元。
- [ ] **Step 7: 编译 + 全量测试** `swift build -c debug && swift test` → 通过。
- [ ] **Step 8: 用户手测暂停**（设置对比设计图⑥；切「跟随系统」生效）。
- [ ] **Step 9: Commit**
```bash
git add VeloxClip/Models/AppSettings.swift VeloxClip/Views/SettingsView.swift Tests/VeloxClipTests/AppearanceTests.swift
git commit -m "feat(settings): follow-system appearance + token-based settings UI"
```

---

## Task 8: ⌘K 命令面板（新功能）

**Files:**
- Create: `VeloxClip/Models/Command.swift`（命令模型 + 解析器）
- Create: `VeloxClip/Views/CommandPaletteView.swift`（浮层 UI）
- Modify: `VeloxClip/Views/MainView.swift`（⌘K 唤起 + overlay 承载）
- Create: `Tests/VeloxClipTests/CommandResolverTests.swift`

- [ ] **Step 1: 写失败测试 —— 命令解析随类型变化**
```swift
import XCTest
@testable import VeloxClip
final class CommandResolverTests: XCTestCase {
    func testColorItemHasHexAndRgbCommands() {
        let ids = CommandResolver.commands(forType: "color").map(\.id)
        XCTAssertTrue(ids.contains("paste"))
        XCTAssertTrue(ids.contains("copyHex"))
        XCTAssertTrue(ids.contains("copyRgb"))
    }
    func testTextItemHasNoColorCommands() {
        let ids = CommandResolver.commands(forType: "text").map(\.id)
        XCTAssertTrue(ids.contains("paste"))
        XCTAssertFalse(ids.contains("copyHex"))
    }
    func testAllTypesHaveCoreCommands() {
        for t in ["text","image","file","rtf"] {
            let ids = CommandResolver.commands(forType: t).map(\.id)
            XCTAssertEqual(Set(["paste","copy","favorite","stack","delete"]).subtracting(ids), [])
        }
    }
}
```
- [ ] **Step 2: 跑测试确认失败** `swift test --filter CommandResolverTests` → FAIL（无 CommandResolver）。
- [ ] **Step 3: 实现 Command 模型 + Resolver**
```swift
import SwiftUI
struct Command: Identifiable {
    let id: String; let title: String; let keyHint: String?; let icon: String
}
enum CommandResolver {
    static func commands(forType type: String) -> [Command] {
        var cmds: [Command] = [
            Command(id: "paste",    title: "粘贴",            keyHint: "⏎",    icon: "doc.on.clipboard"),
            Command(id: "copy",     title: "复制",            keyHint: "⌘C",   icon: "doc.on.doc"),
        ]
        if type == "color" {
            cmds.append(Command(id: "copyHex", title: "复制 HEX", keyHint: nil, icon: "number"))
            cmds.append(Command(id: "copyRgb", title: "复制 RGB", keyHint: nil, icon: "number"))
        }
        cmds.append(contentsOf: [
            Command(id: "favorite", title: "收藏",            keyHint: nil,   icon: "star"),
            Command(id: "stack",    title: "加入 Paste Stack", keyHint: "space", icon: "square.stack"),
            Command(id: "delete",   title: "删除",            keyHint: "⌫",   icon: "trash"),
        ])
        return cmds
    }
}
```
- [ ] **Step 4: 跑测试确认通过** `swift test --filter CommandResolverTests` → PASS。
- [ ] **Step 5: CommandPaletteView UI**：顶部搜索框（显示当前项摘要 + 「动作…」占位）+ 命令列表，选中行 `c.accent` 高亮 + 白字 + 右侧 keyHint 键帽；↑↓ 选择、⏎ 执行、Esc 关闭。接收 `selectedItem` 与 `onExecute(Command)` 闭包。
- [ ] **Step 6: MainView 接线**：`@State private var showCommandPalette = false`；顶部 HStack 加 `.onKeyPress` 监听 `⌘K`（`press.modifiers.contains(.command) && press.characters == "k"`）置 true；`.overlay { if showCommandPalette { CommandPaletteView(item: selectedItem) { cmd in executeCommand(cmd); showCommandPalette = false } } }`。`executeCommand` 派发到现有入口：paste→`WindowManager.selectAndPaste`、favorite→`store.toggleFavorite`、stack→`PasteStackService.shared.toggleStaged`、delete→`store.delete`、copyHex/copyRgb→颜色复制工具、copy→写 pasteboard。
- [ ] **Step 7: 编译 + 全量测试** `swift build -c debug && swift test` → 通过。
- [ ] **Step 8: 用户手测暂停**（⌘K 唤起、选颜色项时出现 HEX/RGB、对比设计图④命令面板）。
- [ ] **Step 9: Commit**
```bash
git add VeloxClip/Models/Command.swift VeloxClip/Views/CommandPaletteView.swift VeloxClip/Views/MainView.swift Tests/VeloxClipTests/CommandResolverTests.swift
git commit -m "feat: ⌘K command palette with type-aware actions"
```

---

## 收尾

- [ ] 全部 8 Task 完成、`swift test` 全绿、用户整体手测通过。
- [ ] 按项目惯例合并到 `main`（feature 分支 + 用户手测后合，[[veloxclip-merge-workflow]]）。
- [ ] 视情况 bump app version（`build_app.sh` / Info）。

## Self-Review 结果

- **Spec 覆盖**：spec §4 的 ①–⑦ 区块分别对应 Task 2/3/4/5/6/7/8；§3 token 层对应 Task 1。无遗漏。
- **Placeholder 扫描**：颜色/字号/圆角均为具体值或注明从渲染 DOM 提取的精确命令；逻辑步骤含真实测试代码。
- **类型一致**：`DSColors`/`DSKeyBadge`/`Command`/`CommandResolver.commands(forType:)` 在定义与引用处命名一致；`appearance` 三值 "light"/"dark"/"system" 贯穿 AppSettings 与 SettingsView。
