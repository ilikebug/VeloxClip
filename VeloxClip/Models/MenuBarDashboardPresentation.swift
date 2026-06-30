import Foundation

enum MenuBarDashboardAction {
    case openClipboard
    case pasteImage
    case captureText
    case settings
    case startQueue
    case resumeQueue
    case cancelQueue
    case clearQueue

    var dismissesPanel: Bool {
        switch self {
        case .clearQueue:
            return false
        case .openClipboard, .pasteImage, .captureText, .settings, .startQueue, .resumeQueue, .cancelQueue:
            return true
        }
    }

    var hidesAppAfterAction: Bool {
        switch self {
        case .startQueue, .resumeQueue, .cancelQueue:
            return true
        case .openClipboard, .pasteImage, .captureText, .settings, .clearQueue:
            return false
        }
    }
}

struct MenuBarDashboardPresentation: Equatable {
    let historyCount: Int
    let favoriteCount: Int
    let stagedCount: Int
    let queueCount: Int
    let cursor: Int
    let phase: PasteStackPhase

    var historyValue: String { "\(historyCount)" }
    var favoriteValue: String { "\(favoriteCount)" }
    var footerShortcutHint: String? { nil }

    var queueValue: String {
        switch phase {
        case .active, .paused, .completed:
            guard queueCount > 0 else { return "0" }
            return "\(min(cursor + 1, queueCount))/\(queueCount)"
        case .idle:
            return stagedCount > 0 ? "\(stagedCount)" : "0"
        }
    }

    var statusText: String {
        statusText()
    }

    func statusText(language: AppLanguage = .zhHans) -> String {
        switch phase {
        case .active:
            return L10n.string("menubar.status.active", language: language)
        case .paused:
            return L10n.string("menubar.status.paused", language: language)
        case .completed:
            return L10n.string("menubar.status.completed", language: language)
        case .idle:
            return stagedCount > 0
                ? L10n.format("menubar.status.staged", stagedCount, language: language)
                : L10n.string("menubar.status.idle", language: language)
        }
    }
}
