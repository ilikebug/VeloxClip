# VeloxClip Windows 移植 — P0:工程脚手架(设计文档)

- 文档日期:2026-05-08
- 子项目:Windows 移植 P0(共 P0–P7,本文件仅覆盖 P0)
- 状态:设计已批准,待实现

## 1. 背景与上下文

VeloxClip 当前是一款仅支持 macOS 的 Swift 6.0 + SwiftUI 剪贴板管理工具,集成了 Apple Vision OCR、Natural Language 向量、OpenRouter LLM、区域截图与图片编辑器等能力。本项目目标是将其完整移植到 Windows,达到**功能 1:1**,UI 遵循 **Windows 11 Fluent Design** 原生设计语言。由于 SwiftUI 与 Apple 私有框架在 Windows 上没有可用对等品,该工作本质上是一次**完整重写**而非代码移植。

整个 Windows 端工作已拆分为 8 个有序子项目(P0–P7,语义搜索作为 v2 后置)。本文件仅设计 **P0 — 工程脚手架**,后续每个子项目独立走 spec → plan → 实现循环。

### 已锁定的总体技术选择(贯穿整个 Windows 端)

| 维度 | 决定 |
|---|---|
| UI 还原度 | 功能 1:1 + Windows 原生 Fluent Design |
| 技术栈 | C# 12 + .NET 8 + Windows App SDK 1.6+ + WinUI 3 |
| 最低系统 | Windows 11 22H2(x64 only) |
| AI 策略 | OCR 用 `Windows.Media.Ocr`;LLM 复用 OpenRouter;**语义搜索移到 v2 后置**,P0–P7 不实现 |
| 仓库策略 | 沿用现有 monorepo,新建顶层 `windows/` 目录 |
| 应用名 / 标识 | `VeloxClip`,Windows 包标识 `com.veloxclip.windows`,产品 ID `VeloxClip.Windows` |
| 发布形式 | GitHub Actions 产出 MSIX(未签名)+ portable zip;暂不上 Microsoft Store / winget |

## 2. P0 范围与非目标

### 2.1 范围(本阶段必做)

P0 不实现任何业务功能。**唯一目标**是搭出一个可构建、可运行、可发布的最小骨架,后续 P1–P7 在其上叠加。

### 2.2 非目标(本阶段不做)

- 任何剪贴板捕获 / 历史 / 搜索 / 收藏 / 标签
- 全局热键、悬浮窗、粘贴回前台
- AI(OCR / LLM)
- 区域截图、图片编辑器
- 设置 UI(P7)
- 代码签名、Microsoft Store 提交、winget 清单
- arm64 构建、Windows 10 兼容
- 自动更新机制

## 3. 仓库布局

```
VeloxClip/                        # 仓库根
├── VeloxClip/                    # 既有 macOS Swift 源码(不动)
├── Package.swift                 # 既有(不动)
├── windows/                      # 新增 — Windows 端根
│   ├── VeloxClip.Windows.sln
│   ├── src/
│   │   ├── VeloxClip.App/        # WinUI 3 启动项目(可执行)
│   │   ├── VeloxClip.Core/       # 业务逻辑(本阶段仅占位,后续填充)
│   │   └── VeloxClip.Platform/   # Win32 P/Invoke、剪贴板、托盘等系统封装
│   ├── tests/
│   │   └── VeloxClip.Core.Tests/ # xUnit
│   ├── build/
│   │   ├── package.ps1           # 本地 MSIX / portable 打包脚本
│   │   └── icons/                # ico / png 资源
│   ├── Directory.Build.props     # 统一 LangVersion / Nullable / TreatWarningsAsErrors
│   ├── Directory.Packages.props  # 集中包版本管理(Central Package Management)
│   └── README.md                 # Windows 端开发说明
├── .github/workflows/
│   ├── build-mac.yml             # 既有
│   └── build-windows.yml         # 新增
└── README.md / CHANGELOG.md      # 增加 Windows 段落
```

### 3.1 项目划分原则

| 项目 | 允许引用 | 禁止引用 | 职责 |
|---|---|---|---|
| `VeloxClip.App` | `Core`, `Platform`, WinUI | — | XAML、App.xaml.cs、DI 装配、窗口与托盘宿主 |
| `VeloxClip.Core` | 仅 .NET 标准库、`CommunityToolkit.Mvvm`、`Microsoft.Extensions.*` | **任何 WinUI / Win32 / WinRT 类型** | 业务模型、ViewModel、服务接口、纯逻辑 |
| `VeloxClip.Platform` | Win32 互操作、WinRT、`Core` 的接口 | XAML / WinUI 视图层 | 实现 `Core` 中定义的系统级接口(剪贴板、热键、托盘等) |

这个边界从 P0 开始就强制,通过 `Directory.Build.props` + `<InternalsVisibleTo>` + 项目引用方向保证;后续阶段添加业务时不会污染逻辑层。

## 4. 关键依赖(集中管理在 `Directory.Packages.props`)

| 包 | 用途 | 引入到 |
|---|---|---|
| `Microsoft.WindowsAppSDK` 1.6.x | WinUI 3 + Windows App SDK 运行时 | `App`, `Platform` |
| `Microsoft.Windows.SDK.BuildTools` | 配套 build 工具 | `App` |
| `H.NotifyIcon.WinUI` | 系统托盘图标(WinUI 3 官方未提供) | `App` |
| `Microsoft.Extensions.Hosting` | DI / 配置 / 日志 / 生命周期 | `App` |
| `Serilog.Extensions.Hosting` + `Serilog.Sinks.File` + `Serilog.Sinks.Debug` | 日志 | `App` |
| `CommunityToolkit.Mvvm` | MVVM source generator | `Core`, `App` |
| `xunit` / `FluentAssertions` | 单元测试 | `Core.Tests` |

**显式不引入**:Prism、ReactiveUI、MahApps、其它重量级 MVVM/UI 框架。

## 5. 启动与生命周期

### 5.1 模式

- **开发期**:WinUI 3 unpackaged 模式(免 MSIX 注册即可调试)
- **CI 产物**:packaged MSIX + 一份 unpackaged portable zip

### 5.2 启动流程

`App.xaml.cs` 仅做三件事:

1. 单实例检查 → 若不是首个实例,把命令行参数转交并退出
2. `Host.CreateApplicationBuilder` 装配 DI、配置、日志
3. 创建主窗口 + 注册托盘图标(若已是首个实例)

### 5.3 退出策略

- 关闭主窗口 ≠ 退出进程:窗口隐藏后保留托盘
- 仅在托盘菜单 **Quit** 时退出(对齐 macOS 菜单栏行为)
- `App.OnSuspending` / `OnExit` 中冲洗 Serilog,确保日志不丢

## 6. 单实例机制

使用 Windows App SDK 内置 `AppInstance.FindOrRegisterForKey("VeloxClip")`(基于 COM 激活)。

- 后到的进程通过 `RedirectActivationToAsync` 把激活事件转给主实例,然后立即退出
- 主实例在 `Activated` 事件中**显示并置顶**主窗口
- **不**自行实现命名 Mutex / 命名管道 —— 官方 API 已覆盖

## 7. 系统托盘

通过 `H.NotifyIcon.WinUI` 在 `App.xaml` 中声明托盘图标。

P0 菜单(共 3 项):

| 菜单项 | 行为 | 状态 |
|---|---|---|
| **Show** | 显示并激活主窗口 | 启用 |
| **Settings** | (P7 之前)— | **置灰** |
| **Quit** | 调用 `Application.Current.Exit()`,进程退出 | 启用 |

托盘图标暂用从 macOS `AppIcon.icns` 转出的 `app.ico`(多尺寸 16/24/32/48/64/128/256),路径 `windows/build/icons/app.ico`。

## 8. 数据 / 设置 / 日志路径

统一根目录:`%LOCALAPPDATA%\VeloxClip\`。

P0 启动时确保下列子目录与文件存在(不存在则创建):

| 路径 | P0 内容 | 后续阶段使用 |
|---|---|---|
| `db\` | 空目录 | P1 SQLite 数据库 |
| `cache\` | 空目录 | P5 LLM 缓存等 |
| `logs\` | 当日 Serilog 日志 | 全阶段 |
| `settings.json` | `{}` 空对象(若不存在) | P7 设置面板 |

日志策略:`logs\veloxclip-YYYYMMDD.log`,按天滚动,保留 7 天,Serilog `RollingInterval.Day`。

## 9. CI:`.github/workflows/build-windows.yml`

### 9.1 触发条件

- `push` 到 `main`
- 任意 `tag`(语义化版本,如 `v1.2.0`)
- `pull_request` 到 `main`

### 9.2 步骤

1. Runner:`windows-2022`
2. 缓存 NuGet 包
3. 安装 `Microsoft.WindowsAppRuntime`(若 runner 默认不带)
4. `dotnet restore windows/VeloxClip.Windows.sln`
5. `dotnet build -c Release` —— 配置中已开启 `TreatWarningsAsErrors`,任何 warning 即失败
6. `dotnet test windows/tests/VeloxClip.Core.Tests`
7. **打包**两种产物:
   - **MSIX**:`dotnet publish src/VeloxClip.App -c Release -p:WindowsPackageType=MSIX -p:Platform=x64 -p:GenerateAppxPackageOnBuild=true`,**未签名**;输出 `VeloxClip-<version>-x64.msix`
   - **Portable zip**:`dotnet publish src/VeloxClip.App -c Release -r win-x64 --self-contained true -p:WindowsPackageType=None -p:PublishSingleFile=false`,把发布目录压成 `VeloxClip-<version>-x64-portable.zip`
8. **仅 tag 触发时**:把两份产物上传到对应 GitHub Release(沿用 mac 端 `release-body` 工作流的所有者/仓库派生模式)

### 9.3 不做的事

- winget 清单提交
- Microsoft Store 提交
- 代码签名 / 公证(留待后续 v1.x 评估)
- arm64 矩阵构建

## 10. 风险与备注

| 风险 | 缓解 |
|---|---|
| MSIX 未签名,用户首次安装需启用 sideload | README 提供详细安装指引;与 Mac 端目前未做公证对称;后续可加 self-signed 证书 |
| WinUI 3 unpackaged 模式下部分 API(toast、部分 AppLifecycle)行为不同 | P0 不依赖这些 API;后续阶段评估时再决定是否切到 packaged-only |
| 仅出 x64,无 arm64 | 与 Mac 端不出 Intel 包策略对称,后续可加 |
| `H.NotifyIcon.WinUI` 是第三方库,WinUI 3 官方未提供托盘 API | 该库维护活跃、社区使用广泛;若未来停滞可降级到 Win32 `Shell_NotifyIcon` P/Invoke |

## 11. P0 完成判据(Definition of Done)

- [ ] `windows/VeloxClip.Windows.sln` 在 Visual Studio 2022 / `dotnet build` 下编译通过,**0 warning 0 error**
- [ ] F5 启动后看到主窗口(标题栏 "VeloxClip",占位文字 "VeloxClip — coming soon")+ 托盘图标
- [ ] 第二次启动同一程序 → 第一个实例窗口被激活置顶,新进程秒退
- [ ] 关闭主窗口 → 进程仍在,托盘仍在;托盘 **Quit** → 进程退出,托盘消失
- [ ] `%LOCALAPPDATA%\VeloxClip\logs\veloxclip-YYYYMMDD.log` 自动创建,启动 / 退出事件均已记录
- [ ] `VeloxClip.Core.Tests` 至少含一条占位 sanity 测试且通过
- [ ] GitHub Actions 在 push 任一分支时构建 + 测试通过;在打 tag 时额外上传 MSIX + portable zip 两份产物到对应 Release
- [ ] `windows/README.md` 提供:环境要求、本地构建命令、本地运行命令、本地打包命令、CI 流程概述

## 12. 后续阶段一览(仅作为 P0 设计的上下文,不在本 spec 范围内)

| 阶段 | 子项目 |
|---|---|
| P1 | 剪贴板核心:监听/捕获(文本/RTF/图片/文件/颜色)、SQLite 存储、5 秒去重、来源应用追踪、历史上限 |
| P2 | 主界面 + 全局热键:Spotlight 风格悬浮窗、列表视图、键盘导航、粘贴回前一应用 |
| P3 | 搜索 + 收藏 + 标签:关键字搜索、收藏体系、内容类型自动打标、自定义标签 + 颜色 |
| P4 | 内容预览组件:JSON / Table / URL / DateTime / Code / Color / File / Image / Markdown |
| P5 | OCR + LLM:Windows.Media.Ocr 集成、OpenRouter 接入(摘要/翻译/解释/润色) |
| P6 | 区域截图 + 图片编辑器:屏幕捕获、画笔/箭头/矩形/圆形/直线/高亮/文本/马赛克/橡皮 |
| P7 | 设置面板 + 黑名单 + 收尾:设置 UI、应用黑名单、快捷键自定义、错误处理、菜单栏图标隐藏 |
| v2(后置) | 语义搜索:本地 ONNX 或云端 embeddings |
