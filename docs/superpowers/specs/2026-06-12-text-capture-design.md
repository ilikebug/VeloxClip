# 屏幕取词(Text Capture / OCR Anywhere)设计

日期:2026-06-12
状态:已与用户确认

## 目标

新增一条与 F1 截图并行的入口:按 F2 框选屏幕任意区域,**识别出的文字直接进剪贴板**(顺带支持二维码解码),框选完即可 Cmd+V。现有 F1 截图 + 后台自动 OCR 链路完全不动。

## 行为

1. F2(默认,可在设置改)→ `screencapture -i -x <临时文件>` 调起系统框选(输出到临时文件,**不污染剪贴板**)。
2. 用户 ESC 取消 → 临时文件不存在 → 静默结束。
3. 识别(后台线程,Vision):
   - 文本:VNRecognizeTextRequest,中英混合,与 AIService 同配置;
   - 二维码/条码:VNDetectBarcodesRequest;
   - **取舍规则:有条码 payload 时优先用 payload(多个换行拼接),否则用 OCR 文本(去首尾空白);两者皆空视为失败。**
4. 成功:文字写入系统剪贴板(走 PasteboardSelfWriteGate)+ 以 `text` 类型直接加进历史(sourceApp = "Text Capture")+ 屏幕角落短暂 toast「✓ Copied N chars」(1.5s 淡出,不抢焦点)。
5. 失败(没识别出内容):toast「No text found」。
6. 临时文件用后即删。

## 实现

- `Services/TextCaptureService.swift` — 主流程 + 识别 + toast;`chooseContent(ocrText:barcodePayloads:)` 为纯函数可单测。
- `ShortcutManager` — 新增 hotkey ID 4(回调里按 ID 分发,需同步加分支)。
- `AppSettings` + `SettingsView` — `textCaptureShortcut` 默认 "f2"。

## 不做

- 不存截图图片;不加历史新类型;不做划词翻译(后续可叠加)。
