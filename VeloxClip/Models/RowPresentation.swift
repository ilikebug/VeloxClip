import Foundation

/// Pure presentation logic for clipboard list rows (Task 9 UI kit).
///
/// No SwiftUI, no `Date()`, no I/O — everything is deterministic given its inputs
/// so the row's icon glyph, metadata subtitle, and relative-time label are unit
/// testable. The view layer (`ClipboardItemRow`) maps these values to tokens.
enum RowIconKind: Equatable {
    case color, image, url, code, json, file, rtf, text
}

struct RowTagBadges: Equatable {
    let visible: [String]
    let overflowCount: Int
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

    // MARK: - Tag badges

    static func visibleTagBadges(from tags: [String], maxVisible: Int) -> RowTagBadges {
        let maxTagCharacters = 12
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { displayTag($0, maxCharacters: maxTagCharacters) }
        let visible = Array(cleaned.prefix(maxVisible))
        return RowTagBadges(
            visible: visible,
            overflowCount: max(0, cleaned.count - visible.count)
        )
    }

    private static func displayTag(_ tag: String, maxCharacters: Int) -> String {
        guard tag.count > maxCharacters else { return tag }
        return String(tag.prefix(max(0, maxCharacters - 3))) + "..."
    }

    // MARK: - File paths

    /// Non-empty path lines from a `file` item's content. Shared by the subtitle
    /// (parent dir) and the row title (file name) so they parse identically.
    static func filePaths(from content: String) -> [String] {
        content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    // MARK: - Subtitle (content metadata)

    /// The second row line: content-specific metadata, never the source app.
    static func subtitle(type: String,
                         content: String?,
                         tags: [String],
                         language: AppLanguage = .zhHans) -> String {
        let kind = iconKind(type: type, tags: tags)

        switch kind {
        case .image:
            // Dimensions need the image blob, which the list view does not load
            // (lazy blob loading). Deviation from the kit: just "图片".
            return L10n.string("row.type.image", language: language)

        case .color:
            let color = L10n.string("row.type.color", language: language)
            guard let content, let rgb = ColorFormatting.rgb(from: content) else { return color }
            let parts = rgb.split(separator: " ")
            guard parts.count == 3 else { return color }
            return "RGB \(parts[0]) · \(parts[1]) · \(parts[2]) · \(color)"

        case .file:
            let file = L10n.string("row.type.file", language: language)
            guard let content else { return file }
            let paths = filePaths(from: content)
            guard let first = paths.first else { return file }
            let parent = URL(fileURLWithPath: first).deletingLastPathComponent().lastPathComponent
            let dir = parent.isEmpty ? "/" : parent
            if paths.count > 1 {
                return "\(L10n.format("row.unit.files", paths.count, language: language)) · \(dir) · \(file)"
            }
            return "\(dir) · \(file)"

        case .url:
            let link = L10n.string("row.type.link", language: language)
            guard let content else { return link }
            let host = URL(string: content)?.host ?? content
            return "\(host) · \(link)"

        case .code:
            let code = L10n.string("row.type.code", language: language)
            guard let content else { return code }
            let lines = content.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return "\(code) · \(L10n.format("row.unit.lines", lines.count, language: language))"

        case .json:
            guard let content else { return "JSON" }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { return "JSON" }
            if let dict = obj as? [String: Any] {
                return "JSON · \(L10n.format("row.unit.keys", dict.count, language: language))"
            }
            if let arr = obj as? [Any] {
                return "JSON · \(L10n.format("row.unit.items", arr.count, language: language))"
            }
            return "JSON"

        case .rtf:
            let rtf = L10n.string("row.type.rtf", language: language)
            guard let content else { return rtf }
            let count = content.trimmingCharacters(in: .whitespacesAndNewlines).count
            return "\(rtf) · \(L10n.format("row.unit.chars", count, language: language))"

        case .text:
            guard let content else { return L10n.string("row.type.unknownContent", language: language) }
            let count = content.trimmingCharacters(in: .whitespacesAndNewlines).count
            return "\(L10n.string("row.type.text", language: language)) · \(L10n.format("row.unit.chars", count, language: language))"
        }
    }

    // MARK: - Relative time

    /// Short relative-time label. `now` is a parameter for testability — the view
    /// passes `Date()`.
    static func relativeTime(_ date: Date,
                             now: Date,
                             language: AppLanguage = .zhHans) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return L10n.string("row.time.justNow", language: language) }
        if seconds < 3600 { return L10n.format("row.time.minutes", Int(seconds / 60), language: language) }
        if seconds < 86_400 { return L10n.format("row.time.hours", Int(seconds / 3600), language: language) }

        let cal = Calendar.current
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) { return L10n.string("row.time.yesterday", language: language) }

        let comps = cal.dateComponents([.month, .day], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        return L10n.format("row.time.monthDay", month, day, language: language)
    }
}
