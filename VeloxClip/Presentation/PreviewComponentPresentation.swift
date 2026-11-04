import Foundation
import NaturalLanguage

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
    private static let formats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "dd/MM/yyyy",
        // Two-digit years, after the four-digit forms so "12/06/2026" still wins there
        "MM/dd/yy",
        "dd/MM/yy",
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss"
    ]

    /// The date a copied string denotes, trying the known text formats and then
    /// a numeric Unix epoch.
    static func date(from string: String, now: Date = Date()) -> Date? {
        // Detection trims newlines; parsing must too, or `date +%s | pbcopy`
        // ("1730000000\n") was classified as a date but never converted
        let source = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar(identifier: .gregorian)
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // DateFormatter is lenient about separators and digit counts:
            // "yyyy-MM-dd" read "12/06/26" as the year 12. No clipboard date is
            // from the first century, so treat that as a miss and keep looking.
            if let date = formatter.date(from: source), calendar.component(.year, from: date) >= 100 {
                return date
            }
        }
        return isoLikeDate(from: source) ?? timeToday(from: source, now: now) ?? unixDate(from: source)
    }

    // The same shapes `ContentDetectionService.isDateTime` accepts. The format
    // list above has no entry for a missing zone, missing seconds or a "/"
    // separator, so "2026-06-12 10:00" and "2026-06-12T10:00:00" were routed
    // here as dates and then shown as plain text.
    // ASCII digits only: `\d` also matches full-width digits ("０５"), which
    // Int(_:) cannot parse — the zone offset force-unwrap trapped on them.
    private static let isoLikePattern = try! NSRegularExpression(
        pattern: #"^([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})(?:[ T]([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$"#)
    private static let timePattern = try! NSRegularExpression(pattern: #"^([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?$"#)

    private static func captures(_ regex: NSRegularExpression, in source: String) -> [String?]? {
        guard let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: source).map { String(source[$0]) } }
    }

    /// Date with optional time, fraction and zone; no zone means local time.
    private static func isoLikeDate(from source: String) -> Date? {
        guard let g = captures(isoLikePattern, in: source) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        if let zone = g[7] {
            var offset = 0
            if zone != "Z" {
                let digits = zone.filter(\.isNumber)
                offset = (Int(digits.prefix(2))! * 3_600 + Int(digits.suffix(2))! * 60) * (zone.hasPrefix("-") ? -1 : 1)
            }
            guard let tz = TimeZone(secondsFromGMT: offset) else { return nil }
            calendar.timeZone = tz
        }
        let components = DateComponents(year: Int(g[0]!), month: Int(g[1]!), day: Int(g[2]!),
                                        hour: g[3].flatMap(Int.init) ?? 0, minute: g[4].flatMap(Int.init) ?? 0,
                                        second: g[5].flatMap(Int.init) ?? 0)
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        return date.addingTimeInterval(g[6].flatMap { Double("0" + $0) } ?? 0)
    }

    /// A bare "14:30" / "14:30:05" is that time today.
    private static func timeToday(from source: String, now: Date) -> Date? {
        guard let g = captures(timePattern, in: source),
              let hour = Int(g[0]!), let minute = Int(g[1]!), hour < 24, minute < 60 else { return nil }
        let second = g[2].flatMap(Int.init) ?? 0
        guard second < 60 else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: second, of: now)
    }

    /// Numeric timestamps: values above 1e11 are milliseconds (13-digit epochs,
    /// which `ContentDetectionService` routes here), otherwise seconds. 1e11 s is
    /// year 5138, so no real seconds value crosses it.
    static func unixDate(from string: String) -> Date? {
        guard let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: value >= 1e11 ? value / 1000 : value)
    }

    /// What the Unix row shows and the Copy-Unix button copies.
    ///
    /// A 13-digit millisecond epoch was divided by 1000 to build the Date, and
    /// then rendered from that Date — handing back a value 1000x smaller than
    /// the one the user copied. When the source IS a numeric epoch, echo it
    /// unchanged; only a formatted date has to be converted.
    static func unixTimestampString(for source: String, parsedDate: Date? = nil) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.allSatisfy(\.isNumber), !trimmed.isEmpty, Double(trimmed) != nil {
            return trimmed
        }
        guard let date = parsedDate ?? unixDate(from: trimmed) else { return nil }
        return String(Int(date.timeIntervalSince1970))
    }

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
        // A future date (a deadline, an expiry) fell into the first branch
        // and read "-86400 seconds ago"; bucket its magnitude and say "in".
        let suffix = seconds < 0 ? "FromNow" : "Ago"
        let seconds = abs(seconds)
        if seconds < 60 {
            return L10n.format("preview.datetime.seconds" + suffix, Int(seconds), language: language)
        } else if seconds < 3_600 {
            return L10n.format("preview.datetime.minutes" + suffix, Int(seconds / 60), language: language)
        } else if seconds < 86_400 {
            return L10n.format("preview.datetime.hours" + suffix, Int(seconds / 3_600), language: language)
        } else if seconds < 604_800 {
            return L10n.format("preview.datetime.days" + suffix, Int(seconds / 86_400), language: language)
        } else {
            return L10n.format("preview.datetime.weeks" + suffix, Int(seconds / 604_800), language: language)
        }
    }
}

struct FilePreviewPresentation {
    /// One ByteCountFormatter configuration for every preview (file list, single file, image info).
    static func fileSizeString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

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
    /// The four header counts, computed once instead of four full string walks
    /// per body pass. This view is routed for `.longtext`, i.e. exactly the
    /// largest items in history.
    struct Stats: Equatable {
        var words: Int
        var characters: Int
        var lines: Int
        var paragraphs: Int

        static let empty = Stats(words: 0, characters: 0, lines: 0, paragraphs: 0)
    }

    static func stats(for text: String) -> Stats {
        Stats(
            words: text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count,
            characters: text.count,
            lines: text.components(separatedBy: .newlines).count,
            paragraphs: paragraphs(in: text).count
        )
    }

    /// Non-empty paragraphs, the unit the preview pages through.
    static func paragraphs(in text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The first three sentences, as written. Splitting on ASCII ".!?" never
    /// split Chinese ("。！？"), so the "summary" was the whole text plus ".".
    static func summary(for text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var end = text.startIndex
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            end = range.upperBound
            count += 1
            return count < 3
        }
        return text[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The ten most frequent words. Splitting on non-alphanumerics left a run of
    /// Chinese as one "word", so the keywords were whole sentences; a word
    /// tokenizer segments it. Latin words still need four letters, CJK two.
    static func keywords(in text: String) -> [String] {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered
        var wordCounts: [String: Int] = [:]
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let word = String(lowered[range])
            if word.count > 3 || (word.count >= 2 && !word.allSatisfy(\.isASCII)) {
                wordCounts[word, default: 0] += 1
            }
            return true
        }
        return Array(wordCounts.sorted { $0.value > $1.value }.prefix(10).map(\.key))
    }

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
