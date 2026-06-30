import Foundation

struct TablePreviewPresentation {
    static var formatLabel: String { formatLabel() }
    static var searchPlaceholder: String { searchPlaceholder() }
    static var emptyMessage: String { emptyMessage() }
    static var loadingMoreRowsTitle: String { loadingMoreRowsTitle() }

    static func formatLabel(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.table.delimiter", language: language)
    }

    static func searchPlaceholder(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.table.search", language: language)
    }

    static func emptyMessage(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.table.empty", language: language)
    }

    static func loadingMoreRowsTitle(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.table.loadingMoreRows", language: language)
    }

    static func delimiterLabel(for delimiter: String, language: AppLanguage = L10n.currentLanguage) -> String {
        switch delimiter {
        case "\t": return L10n.string("preview.table.delimiter.tsv", language: language)
        case "|": return L10n.string("preview.table.delimiter.pipe", language: language)
        default: return L10n.string("preview.table.delimiter.csv", language: language)
        }
    }

    static func rowColumnSummary(rows: Int,
                                 columns: Int,
                                 language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.format("preview.table.summary", rows, columns, language: language)
    }
}

struct DateTimePreviewPresentation {
    static var title: String { title() }
    static var copyISOButtonTitle: String { copyISOButtonTitle() }
    static var copyUnixButtonTitle: String { copyUnixButtonTitle() }
    static var copyAllButtonTitle: String { copyAllButtonTitle() }

    static func title(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.datetime.title", language: language)
    }

    static func copyISOButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.datetime.copyISO", language: language)
    }

    static func copyUnixButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.datetime.copyUnix", language: language)
    }

    static func copyAllButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.string("preview.datetime.copyAll", language: language)
    }

    static func relativeTime(secondsAgo seconds: TimeInterval,
                             language: AppLanguage = L10n.currentLanguage) -> String {
        if seconds < 60 {
            return L10n.format("preview.datetime.secondsAgo", Int(seconds), language: language)
        } else if seconds < 3_600 {
            return L10n.format("preview.datetime.minutesAgo", Int(seconds / 60), language: language)
        } else if seconds < 86_400 {
            return L10n.format("preview.datetime.hoursAgo", Int(seconds / 3_600), language: language)
        } else if seconds < 604_800 {
            return L10n.format("preview.datetime.daysAgo", Int(seconds / 86_400), language: language)
        } else {
            return L10n.format("preview.datetime.weeksAgo", Int(seconds / 604_800), language: language)
        }
    }
}

struct FilePreviewPresentation {
    static var missingBadge: String { missingBadge() }
    static var detailsTitle: String { detailsTitle() }
    static var sizeLabel: String { sizeLabel() }
    static var typeLabel: String { typeLabel() }
    static var modifiedLabel: String { modifiedLabel() }
    static var openFileButtonTitle: String { openFileButtonTitle() }
    static var revealInFinderButtonTitle: String { revealInFinderButtonTitle() }
    static var copyPathButtonTitle: String { copyPathButtonTitle() }
    static var copyNameButtonTitle: String { copyNameButtonTitle() }
    static var fileDoesNotExistMessage: String { fileDoesNotExistMessage() }
    static var revealInFinderHelp: String { revealInFinderButtonTitle() }
    static var copySingleFileHelp: String { copySingleFileHelp() }
    static var unknownType: String { unknownType() }
    static var genericFileType: String { genericFileType() }

    static func missingBadge(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.missing", language: language) }
    static func detailsTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.details", language: language) }
    static func sizeLabel(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.size", language: language) }
    static func typeLabel(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.type", language: language) }
    static func modifiedLabel(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.modified", language: language) }
    static func openFileButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.open", language: language) }
    static func revealInFinderButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.reveal", language: language) }
    static func copyPathButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.copyPath", language: language) }
    static func copyNameButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.copyName", language: language) }
    static func fileDoesNotExistMessage(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.notExist", language: language) }
    static func copySingleFileHelp(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.copySingleHelp", language: language) }
    static func unknownType(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.unknown", language: language) }
    static func genericFileType(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.file.generic", language: language) }

    static func filesTitle(count: Int, language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.format("preview.file.count", count, language: language)
    }

    static func missingSummary(count: Int, language: AppLanguage = L10n.currentLanguage) -> String {
        L10n.format("preview.file.missingCount", count, language: language)
    }
}

struct TextSummaryPresentation {
    static var wordsLabel: String { wordsLabel() }
    static var charactersLabel: String { charactersLabel() }
    static var linesLabel: String { linesLabel() }
    static var paragraphsLabel: String { paragraphsLabel() }
    static var summaryTitle: String { summaryTitle() }
    static var copyButtonTitle: String { copyButtonTitle() }
    static var keywordsTitle: String { keywordsTitle() }
    static var generateSummaryButtonTitle: String { generateSummaryButtonTitle() }
    static var showSummaryTitle: String { showSummaryTitle() }
    static var showFullTextTitle: String { showFullTextTitle() }
    static var loadingMoreParagraphsTitle: String { loadingMoreParagraphsTitle() }

    static func wordsLabel(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.words", language: language) }
    static func charactersLabel(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.characters", language: language) }
    static func linesLabel(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.lines", language: language) }
    static func paragraphsLabel(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.paragraphs", language: language) }
    static func summaryTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.summary", language: language) }
    static func copyButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.copy", language: language) }
    static func keywordsTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.keywords", language: language) }
    static func generateSummaryButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.generateSummary", language: language) }
    static func showSummaryTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.showSummary", language: language) }
    static func showFullTextTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.showFullText", language: language) }
    static func loadingMoreParagraphsTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.loadingMoreParagraphs", language: language) }
}

struct TextToolsPresentation {
    static var uppercaseButtonTitle: String { uppercaseButtonTitle() }
    static var lowercaseButtonTitle: String { lowercaseButtonTitle() }
    static var cleanupWhitespaceButtonTitle: String { cleanupWhitespaceButtonTitle() }

    static func uppercaseButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.uppercase", language: language) }
    static func lowercaseButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.lowercase", language: language) }
    static func cleanupWhitespaceButtonTitle(language: AppLanguage = L10n.currentLanguage) -> String { L10n.string("preview.text.cleanupWhitespace", language: language) }
}
