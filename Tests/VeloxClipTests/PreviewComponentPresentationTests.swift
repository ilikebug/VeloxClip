import XCTest
@testable import VeloxClip

final class PreviewComponentPresentationTests: XCTestCase {
    func testTablePreviewLabelsAreLocalizedAndSpecific() {
        XCTAssertEqual(TablePreviewPresentation.formatLabel(language: .zhHans), "分隔符")
        XCTAssertEqual(TablePreviewPresentation.searchPlaceholder(language: .zhHans), "搜索...")
        XCTAssertEqual(TablePreviewPresentation.emptyMessage(language: .zhHans), "未找到表格数据")
        XCTAssertEqual(TablePreviewPresentation.rowColumnSummary(rows: 2, columns: 3, language: .zhHans), "2 行，3 列")
        XCTAssertEqual(TablePreviewPresentation.delimiterLabel(for: "\t", language: .zhHans), "TSV（制表符）")
        XCTAssertEqual(TablePreviewPresentation.delimiterLabel(for: "|", language: .zhHans), "竖线（|）")
        XCTAssertEqual(TablePreviewPresentation.delimiterLabel(for: ",", language: .zhHans), "CSV（,）")
        XCTAssertEqual(TablePreviewPresentation.formatLabel(language: .en), "Delimiter")
        XCTAssertEqual(TablePreviewPresentation.rowColumnSummary(rows: 2, columns: 3, language: .en), "2 rows, 3 columns")
    }

    func testDateTimePreviewLabelsAreLocalized() {
        XCTAssertEqual(DateTimePreviewPresentation.title(language: .zhHans), "日期/时间格式")
        XCTAssertEqual(DateTimePreviewPresentation.copyISOButtonTitle(language: .zhHans), "复制 ISO")
        XCTAssertEqual(DateTimePreviewPresentation.copyUnixButtonTitle(language: .zhHans), "复制 Unix")
        XCTAssertEqual(DateTimePreviewPresentation.copyAllButtonTitle(language: .zhHans), "复制全部")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 45, language: .zhHans), "45 秒前")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 120, language: .zhHans), "2 分钟前")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 7_200, language: .zhHans), "2 小时前")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 172_800, language: .zhHans), "2 天前")
        XCTAssertEqual(DateTimePreviewPresentation.title(language: .en), "Date/Time Formats")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 120, language: .en), "2 minutes ago")
    }

    func testFilePreviewLabelsAreLocalized() {
        XCTAssertEqual(FilePreviewPresentation.filesTitle(count: 3, language: .zhHans), "3 个文件")
        XCTAssertEqual(FilePreviewPresentation.missingSummary(count: 2, language: .zhHans), "2 个缺失")
        XCTAssertEqual(FilePreviewPresentation.missingBadge(language: .zhHans), "缺失")
        XCTAssertEqual(FilePreviewPresentation.detailsTitle(language: .zhHans), "文件详情")
        XCTAssertEqual(FilePreviewPresentation.openFileButtonTitle(language: .zhHans), "打开文件")
        XCTAssertEqual(FilePreviewPresentation.revealInFinderButtonTitle(language: .zhHans), "在 Finder 中显示")
        XCTAssertEqual(FilePreviewPresentation.copyPathButtonTitle(language: .zhHans), "复制路径")
        XCTAssertEqual(FilePreviewPresentation.copyNameButtonTitle(language: .zhHans), "复制名称")
        XCTAssertEqual(FilePreviewPresentation.fileDoesNotExistMessage(language: .zhHans), "文件不存在")
        XCTAssertEqual(FilePreviewPresentation.filesTitle(count: 3, language: .en), "3 files")
        XCTAssertEqual(FilePreviewPresentation.detailsTitle(language: .en), "File Details")
    }

    func testTextSummaryLabelsAreLocalized() {
        XCTAssertEqual(TextSummaryPresentation.wordsLabel(language: .zhHans), "词数")
        XCTAssertEqual(TextSummaryPresentation.charactersLabel(language: .zhHans), "字符")
        XCTAssertEqual(TextSummaryPresentation.linesLabel(language: .zhHans), "行数")
        XCTAssertEqual(TextSummaryPresentation.paragraphsLabel(language: .zhHans), "段落")
        XCTAssertEqual(TextSummaryPresentation.summaryTitle(language: .zhHans), "摘要")
        XCTAssertEqual(TextSummaryPresentation.keywordsTitle(language: .zhHans), "关键词")
        XCTAssertEqual(TextSummaryPresentation.generateSummaryButtonTitle(language: .zhHans), "生成摘要")
        XCTAssertEqual(TextSummaryPresentation.showSummaryTitle(language: .zhHans), "显示摘要")
        XCTAssertEqual(TextSummaryPresentation.showFullTextTitle(language: .zhHans), "显示全文")
        XCTAssertEqual(TextSummaryPresentation.loadingMoreParagraphsTitle(language: .zhHans), "加载更多段落...")
        XCTAssertEqual(TextSummaryPresentation.wordsLabel(language: .en), "Words")
        XCTAssertEqual(TextSummaryPresentation.showFullTextTitle(language: .en), "Show Full Text")
    }

    func testTextToolLabelsAreLocalized() {
        XCTAssertEqual(TextToolsPresentation.uppercaseButtonTitle(language: .zhHans), "转大写")
        XCTAssertEqual(TextToolsPresentation.lowercaseButtonTitle(language: .zhHans), "转小写")
        XCTAssertEqual(TextToolsPresentation.cleanupWhitespaceButtonTitle(language: .zhHans), "清理空白")
        XCTAssertEqual(TextToolsPresentation.uppercaseButtonTitle(language: .en), "Uppercase")
    }
}
