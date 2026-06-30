import Foundation

/// Pure presentation logic for clipboard list rows (Task 9 UI kit).
///
/// No SwiftUI, no `Date()`, no I/O — everything is deterministic given its inputs
/// so the row's icon glyph, metadata subtitle, and relative-time label are unit
/// testable. The view layer (`ClipboardItemRow`) maps these values to tokens.
enum RowIconKind: Equatable {
    case color, image, url, code, json, file, rtf, text
}

enum RowPresentation {

    // MARK: - Icon kind

    /// Which content glyph (or swatch / thumbnail) a row shows.
    /// `color` / `image` / `file` are decided by the item type (they own the leading
    /// visual regardless of tags); other types fall back to url/code/json by tag,
    /// then to rtf/text by type.
    static func iconKind(type: String, tags: [String]) -> RowIconKind {
        switch type {
        case "color": return .color
        case "image": return .image
        case "file":  return .file
        default: break
        }

        // Real tag strings (ClipboardMonitor.detectTags) are capitalized: URL/Code/JSON.
        // Match case-insensitively so either casing works.
        let lower = Set(tags.map { $0.lowercased() })
        if lower.contains("url")  { return .url }
        if lower.contains("json") { return .json }
        if lower.contains("code") { return .code }

        return type == "rtf" ? .rtf : .text
    }

    // MARK: - File paths

    /// Non-empty path lines from a `file` item's content. Shared by the subtitle
    /// (parent dir) and the row title (file name) so they parse identically.
    static func filePaths(from content: String) -> [String] {
        content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    // MARK: - Subtitle (content metadata)

    /// The second row line: content-specific metadata, never the source app.
    static func subtitle(type: String, content: String?, tags: [String]) -> String {
        let kind = iconKind(type: type, tags: tags)

        switch kind {
        case .image:
            // Dimensions need the image blob, which the list view does not load
            // (lazy blob loading). Deviation from the kit: just "图片".
            return "图片"

        case .color:
            guard let content, let rgb = ColorFormatting.rgb(from: content) else { return "颜色" }
            let parts = rgb.split(separator: " ")
            guard parts.count == 3 else { return "颜色" }
            return "RGB \(parts[0]) · \(parts[1]) · \(parts[2]) · 颜色"

        case .file:
            guard let content else { return "文件" }
            let paths = filePaths(from: content)
            guard let first = paths.first else { return "文件" }
            let parent = URL(fileURLWithPath: first).deletingLastPathComponent().lastPathComponent
            let dir = parent.isEmpty ? "/" : parent
            if paths.count > 1 {
                return "\(paths.count) 个文件 · \(dir) · 文件"
            }
            return "\(dir) · 文件"

        case .url:
            guard let content else { return "链接" }
            let host = URL(string: content)?.host ?? content
            return "\(host) · 链接"

        case .code:
            guard let content else { return "代码" }
            let lines = content.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return "代码 · \(lines.count) 行"

        case .json:
            guard let content else { return "JSON" }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { return "JSON" }
            if let dict = obj as? [String: Any] {
                return "JSON · \(dict.count) 个键"
            }
            if let arr = obj as? [Any] {
                return "JSON · \(arr.count) 项"
            }
            return "JSON"

        case .rtf:
            guard let content else { return "富文本" }
            let count = content.trimmingCharacters(in: .whitespacesAndNewlines).count
            return "富文本 · \(count) 字"

        case .text:
            guard let content else { return "未知内容" }
            let count = content.trimmingCharacters(in: .whitespacesAndNewlines).count
            return "纯文本 · \(count) 字"
        }
    }

    // MARK: - Relative time

    /// Short relative-time label. `now` is a parameter for testability — the view
    /// passes `Date()`.
    static func relativeTime(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) 小时" }

        let cal = Calendar.current
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) { return "昨天" }

        let comps = cal.dateComponents([.month, .day], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        return "\(month)月\(day)日"
    }
}
