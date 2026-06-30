# VeloxClip 界面套件还原 — 设计文档

**日期：** 2026-06-30
**目标：** 按设计图《VeloxClip 界面套件》逐像素还原全部界面，并新增 ⌘K 命令面板。
**设计图源文件：** `~/Desktop/VeloxClip 界面套件.html`（bundled HTML，需浏览器渲染）。
渲染参考：`/Applications/Google Chrome.app/.../Google Chrome --headless=new --dump-dom <file>` 可取得展开后的真实 DOM 与内联样式，用于在实现期提取精确像素值。

## 1. 背景与现状

VeloxClip 当前 UI 使用一套**紫→靛渐变**（`DesignSystem.primaryGradient` = `#6366f1 → #a855f7`）与 `.rounded` 字体设计。设计图则是一套**纯平、无渐变、系统蓝 `#0A84FF`** 的 SF 系统字体语言。两者是根本性的视觉语言差异。

`primaryGradient` 当前被 5 个文件引用：
`DesignSystem.swift`、`MainView.swift`、`PreviewView.swift`、`PasteStackHUD.swift`、`ScreenshotEditorView.swift`。

设计图覆盖 6+1 个区块，其中**⌘K 命令面板为全新功能**（代码中不存在）；外观设置当前仅 Light/Dark，设计图新增「跟随系统」与「强调色跟随系统」。

## 2. 关键决策（已与用户确认）

1. **范围：** 全部 6 区块一次性规划，⌘K 命令面板作为最后一步实现。
2. **还原度：** 尽量逐像素一致（配色/间距/圆角/字号/控件样式严格对齐设计图；字体渲染、阴影以 macOS 原生为准）。
3. **深色模式：** 浅色逐像素对齐设计图；深色由同一逻辑**推导**一套 token（深色画布/面板/分割线），强调色保持 `#0A84FF` 系。
4. **强调色：** 跟随系统强调色（设计图标注「强调色跟随系统」），默认值落在 `#0A84FF`。
5. **Harness 分工：** 每步由 Claude 跑 `swift build -c debug` + `swift test`（相关 filter）确保编译/测试通过；**界面截图与手动验证由用户完成**；在 feature 分支上推进，用户手测通过后才合 `main`（遵循项目惯例 [[veloxclip-merge-workflow]]）。

## 3. 设计 Token 系统（基础层）

逐像素来源 —— 设计图根节点 CSS 变量（浅色）：

| Token (Swift) | 浅色值 | 深色推导值 | 用途 |
|---|---|---|---|
| `dsAccent` | `#0A84FF`（跟随系统强调色，回退此值） | 同（系统蓝在深色下原生即更亮） | 选中态、主按钮、开关、徽章、链接 |
| `dsAccentSoft` | `rgba(10,132,255,.14)` | `rgba(10,132,255,.22)` | 强调色浅底 |
| `dsText` | `#1d1d1f` | `#f5f5f7` | 主文本 |
| `dsText2` | `#86868b` | `#98989d` | 次要文本 |
| `dsText3` | `#aeaeb2` | `#636366` | 三级文本/占位 |
| `dsWindow` | `#f4f3f1` | `#1e1e1e` | 窗口背景 |
| `dsPanel` | `rgba(250,250,249,.78)` | `rgba(40,40,42,.80)` | 浮层面板 |
| `dsCard` | `#ffffff` | `#2c2c2e` | 内层卡片 |
| `dsField` | `rgba(0,0,0,.055)` | `rgba(255,255,255,.08)` | 输入框填充 |
| `dsChip` | `rgba(0,0,0,.05)` | `rgba(255,255,255,.07)` | 筛选/标签 chip 填充 |
| `dsKey` | `rgba(0,0,0,.06)` | `rgba(255,255,255,.10)` | 键盘徽章填充 |
| `dsDivider` | `rgba(0,0,0,.09)` | `rgba(255,255,255,.12)` | 0.5px 分割线 |
| `dsHover` | `rgba(0,0,0,.045)` | `rgba(255,255,255,.06)` | 行 hover |
| `dsShadow` | `0 18px 50px rgba(0,0,0,.2)` | `0 18px 50px rgba(0,0,0,.5)` | 面板投影 |

**尺度系统：**
- 圆角：控件 6/7/8px，面板 12/13/14px，胶囊 20px。
- 字号：正文 11–13.5px，区块标题 20px；新增 token：`dsCaption=11`、`dsBody=13`、`dsBody2=13.5`（已有 `dsBody=13` 可复用，必要时补 13.5）。
- 字重：500–620（无重粗体）；移除所有 `.rounded` design，统一 SF 默认。
- **全局无渐变。**

**新增组件：**
- `DSKeyBadge`：渲染 `⌘1` / `⏎` / `space` 等键帽（`dsKey` 填充、圆角 4–5px、10.5–11px 字）。
- 重写 `DSButtonStyle`：`.prominent` 改为 `dsAccent` 纯色填充（去渐变）；`DSSwitchToggleStyle`、`DSSlider` 的渐变改 `dsAccent`。
- token 提供 `@Environment(\.colorScheme)` 感知的浅/深取值（统一入口，避免散落判断）。

**迁移：** 删除 `primaryGradient`，5 个引用文件全部改为 `dsAccent`。

## 4. 分区改造清单

### ① 主浮层 MainView（`MainView.swift` + `ClipboardListView.swift`）
- 搜索栏：紧凑高度、左放大镜（去渐变、改 `dsText2`/`dsAccent`）、右侧 `⌘V` 键帽提示；去掉 18px `.rounded` 字，改 SF。
- **历史/收藏分段标签**替换右上角星形 toggle；其右侧并排放**类型筛选 chip**（全部/文本/图片/文件），chip 选中 = `dsAccent` 纯色、未选 = `dsChip`。
- 列表行：**选中态 = `dsAccent` 纯色填充 + 白字 + 右侧 ⏎ 键帽**（替换当前 `accentColor.opacity(0.25)`）；每行右侧显示 **⌘1–⌘6 键帽**（前 9 行）；类型图标底色用 `dsAccentSoft`/对应淡色。
- **底部操作栏**（新增）：`粘贴 · 详情 · space 入栈 · ⌘K 动作 · N 条`，分割线 0.5px，键帽用 `DSKeyBadge`。
- 整窗背景由 `backgroundBlur` 调整为 `dsPanel`/material 一致观感；外框圆角与投影对齐 `dsShadow`。

### ② 空态 / 收藏态
- 无历史：居中图标 + 「还没有剪贴记录 / 复制点什么，这里就会出现」。
- 搜索无结果：「无匹配 / 试别的词，或切到收藏」。
- 收藏视图：与历史同构的行布局（含 ★ 标记）。

### ③ 详情视图 PreviewView（`PreviewView.swift` + `PreviewComponents/*`）
- 统一头部：`‹ 返回 · 标题 · ★ · ✕` + 下方标签 chip 行；去渐变。
- 五类预览（颜色/链接/图片/代码/JSON）改 token：颜色页 HEX/RGB/HSL 行用 `dsField` + 复制按钮；链接页 QR + 「打开链接」主按钮（`dsAccent`）+ 「复制」次按钮；图片页 占位斜纹 + 图中文字区；代码/JSON 用等宽体 + 行号 + `dsCard` 底。

### ④ Paste Stack HUD（`PasteStackHUD.swift`）
- 三态还原：**进行中**（标题 + `n / m` + 行列表，当前项高亮 `dsAccent` + ⏎）、**暂停-检测到新复制**（黄条提示 + 继续/放弃 双按钮）、**完成**（蓝色对勾圆 + 「已粘贴 N 项」）。
- 去渐变；位置说明文案「位置可在设置中改 · 默认右下角」。

### ⑤ 截图标注编辑器（`ScreenshotEditorView.swift`）
- 工具栏：选择/笔/箭头/矩形/椭圆/文字/马赛克 + 颜色点（红/蓝/黄/黑）+ 粗细 + 撤销/重做 + 「完成」主按钮（`dsAccent`）。
- 去渐变；选中工具高亮 `dsAccent`。

### ⑥ 设置 SettingsView（`SettingsView.swift` + `AppSettings.swift`）
- 左侧分栏：外观 / 历史 / Paste Stack / 快捷键 / 高级。
- **外观**：主题分段 = 浅色 / 深色 / **跟随系统**（新增第三项，`AppSettings.appearance` 增加 `"system"`，`applyAppearance()` 置 `NSApp.appearance = nil` 跟随系统）；**强调色 跟随系统**（展示系统强调色圆点 + 说明）。
- **历史**：历史上限分段 50/100/500/1000；开机启动 DSSwitch。
- **Paste Stack**：显示进度浮窗 DSSwitch；浮窗位置 2×2/网格选择器。
- **快捷键**：唤起浮层 `⌘⇧V`、截图标注 `F1`、屏幕取词 `F2`、粘贴图片 `F3`（DSKeyBadge）。
- 底部：清缓存 / 清历史（destructive）。
- 全部控件用 DesignSystem 基元（遵循 [[ui-consistency-conventions]]）。

### ⑦ ⌘K 命令面板（全新，最后一步）
- 触发：主浮层内按 `⌘K` 弹出动作列表浮层（搜索框 + 列表）。
- **上下文相关**：动作随选中项类型变化。通用：粘贴(⏎)、复制(⌘C)、收藏、加入 Paste Stack(space)、删除(⌫)；当选中项为颜色时追加：复制 HEX、复制 RGB。
- 键盘驱动：↑↓ 选择、⏎ 执行、Esc 关闭；选中行 `dsAccent` 高亮。
- 复用现有动作入口（`WindowManager.selectAndPaste`、`store` 收藏/删除、`PasteStackService.toggleStaged`、颜色复制工具）。

## 5. 执行顺序（每步独立可验证）

1. **Token 基础层** —— 重写 `DesignSystem.swift`，迁移 5 个 `primaryGradient` 引用，新增 `DSKeyBadge` 与浅/深 token。编译通过、现有测试通过、视觉无明显回归。
2. **主浮层** —— MainView + ClipboardListView（分段标签、类型 chip、选中态、⌘N 键帽、底部操作栏）。
3. **空态/收藏态**。
4. **详情视图** —— PreviewView + 5 个 PreviewComponents。
5. **Paste Stack HUD** —— 三态。
6. **截图标注编辑器**。
7. **设置** —— 含「跟随系统」外观 + 强调色跟随系统。
8. **⌘K 命令面板**（新功能）。

Token 先行，保证后续每步都建立在纯平系统蓝之上。

## 6. 每步 Harness

每个步骤：
1. 在 feature 分支实现改动（仅用 DesignSystem 基元，禁用系统默认控件/语义字体 [[ui-consistency-conventions]]）。
2. Claude 跑 `swift build -c debug`，编译通过。
3. Claude 跑相关 `swift test`（如 `ClipboardStoreTests`、`ClipboardTypeFilterTests`、`PasteStackServiceTests` 等），通过。
4. Claude 暂停，**用户运行 App、截图、与设计图对比手测**。
5. 用户确认无误后进入下一步。
6. 全部完成、用户整体手测通过后，再合并到 `main`（遵循 [[veloxclip-merge-workflow]]）。

## 7. 范围边界（YAGNI）

- 不改数据层/并发模型/DB schema；纯 UI 与（⌘K 所需的）轻量视图状态。
- 不新增设计图未出现的功能；⌘K 仅暴露已存在的动作。
- 不追求字体光栅化/阴影与设计图截图的逐像素 diff（以 macOS 原生渲染为准）。
- 深色 token 为推导值，非设计图给定，验收以「同一视觉逻辑、协调一致」为准。

## 8. 风险

- **全局去渐变**改变品牌观感 —— 设计图明确要求「无渐变」，遵循。
- **强调色跟随系统** —— 用户系统强调色非蓝时，选中态会变色；与设计图截图（蓝）会有差异，但符合「强调色跟随系统」标注。
- **菜单栏 App 截图验证**依赖用户本地授权环境，故截图验证交由用户。
