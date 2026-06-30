import Foundation

struct TablePreviewPresentation {
    static let formatLabel = "分隔符"
    static let searchPlaceholder = "搜索..."
    static let emptyMessage = "未找到表格数据"
    static let loadingMoreRowsTitle = "加载更多行..."

    static func delimiterLabel(for delimiter: String) -> String {
        switch delimiter {
        case "\t": return "TSV（制表符）"
        case "|": return "竖线（|）"
        default: return "CSV（,）"
        }
    }

    static func rowColumnSummary(rows: Int, columns: Int) -> String {
        "\(rows) 行，\(columns) 列"
    }
}

struct DateTimePreviewPresentation {
    static let title = "日期/时间格式"
    static let copyISOButtonTitle = "复制 ISO"
    static let copyUnixButtonTitle = "复制 Unix"
    static let copyAllButtonTitle = "复制全部"

    static func relativeTime(secondsAgo seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) 秒前"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60)) 分钟前"
        } else if seconds < 86_400 {
            return "\(Int(seconds / 3_600)) 小时前"
        } else if seconds < 604_800 {
            return "\(Int(seconds / 86_400)) 天前"
        } else {
            return "\(Int(seconds / 604_800)) 周前"
        }
    }
}

struct FilePreviewPresentation {
    static let missingBadge = "缺失"
    static let detailsTitle = "文件详情"
    static let sizeLabel = "大小"
    static let typeLabel = "类型"
    static let modifiedLabel = "修改时间"
    static let openFileButtonTitle = "打开文件"
    static let revealInFinderButtonTitle = "在 Finder 中显示"
    static let copyPathButtonTitle = "复制路径"
    static let copyNameButtonTitle = "复制名称"
    static let fileDoesNotExistMessage = "文件不存在"
    static let revealInFinderHelp = "在 Finder 中显示"
    static let copySingleFileHelp = "只复制这个文件"
    static let unknownType = "未知"
    static let genericFileType = "文件"

    static func filesTitle(count: Int) -> String {
        "\(count) 个文件"
    }

    static func missingSummary(count: Int) -> String {
        "\(count) 个缺失"
    }
}

struct TextSummaryPresentation {
    static let wordsLabel = "词数"
    static let charactersLabel = "字符"
    static let linesLabel = "行数"
    static let paragraphsLabel = "段落"
    static let summaryTitle = "摘要"
    static let copyButtonTitle = "复制"
    static let keywordsTitle = "关键词"
    static let generateSummaryButtonTitle = "生成摘要"
    static let showSummaryTitle = "显示摘要"
    static let showFullTextTitle = "显示全文"
    static let loadingMoreParagraphsTitle = "加载更多段落..."
}

struct TextToolsPresentation {
    static let uppercaseButtonTitle = "转大写"
    static let lowercaseButtonTitle = "转小写"
    static let cleanupWhitespaceButtonTitle = "清理空白"
}
