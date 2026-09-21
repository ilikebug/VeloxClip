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
        label(language: .zhHans)
    }

    func label(language: AppLanguage = .zhHans) -> String {
        switch self {
        case .all: return L10n.string("filter.all", language: language)
        case .text: return L10n.string("filter.text", language: language)
        case .image: return L10n.string("filter.image", language: language)
        case .file: return L10n.string("filter.file", language: language)
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
