import Foundation

// List type-filter chips (All / Text / Image / File) shown above the history list.
// "Text" aggregates the textual item types: plain text, RTF, and color strings.
enum ClipboardTypeFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return item.type == "text" || item.type == "rtf" || item.type == "color"
        case .image:
            return item.type == "image"
        case .file:
            return item.type == "file"
        }
    }
}
