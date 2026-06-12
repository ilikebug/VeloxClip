# 列表类型筛选栏设计

日期:2026-06-12
状态:已与用户确认(用户提供截图标注)

## 目标

在历史列表顶部加一行类型筛选 chips:`All / Text / Image / File`,点击后列表只显示对应类型。

## 规则

- **Text 聚合**纯文本、RTF、颜色三种类型;Image = image;File = file;All 不过滤(默认)。
- 筛选与搜索词、收藏视图**叠加生效**(在过滤后的集合上展示)。
- 每次重新打开浮窗重置为 All(与搜索框清空一致,挂在 `.veloxOverlayWillShow`)。
- 切换筛选后若当前选中项不在结果里,自动选中第一条。
- 无键盘快捷键(Tab 已被收藏切换占用),纯点击。

## 实现

- `Models/ClipboardTypeFilter.swift` — enum + `matches(_:)` 纯函数(可单测)。
- `MainView` — `@State typeFilter`,`displayItems` 统一套用过滤;chips 条放在左侧列表列顶部;样式沿用 DesignSystem。
- 单测:`ClipboardTypeFilterTests`(每个筛选项的命中/不命中)。
