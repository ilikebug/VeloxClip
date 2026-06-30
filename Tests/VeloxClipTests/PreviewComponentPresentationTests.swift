import XCTest
@testable import VeloxClip

final class PreviewComponentPresentationTests: XCTestCase {
    func testTablePreviewLabelsAreLocalizedAndSpecific() {
        XCTAssertEqual(TablePreviewPresentation.formatLabel, "分隔符")
        XCTAssertEqual(TablePreviewPresentation.searchPlaceholder, "搜索...")
        XCTAssertEqual(TablePreviewPresentation.emptyMessage, "未找到表格数据")
        XCTAssertEqual(TablePreviewPresentation.rowColumnSummary(rows: 2, columns: 3), "2 行，3 列")
        XCTAssertEqual(TablePreviewPresentation.delimiterLabel(for: "\t"), "TSV（制表符）")
        XCTAssertEqual(TablePreviewPresentation.delimiterLabel(for: "|"), "竖线（|）")
        XCTAssertEqual(TablePreviewPresentation.delimiterLabel(for: ","), "CSV（,）")
    }

    func testDateTimePreviewLabelsAreLocalized() {
        XCTAssertEqual(DateTimePreviewPresentation.title, "日期/时间格式")
        XCTAssertEqual(DateTimePreviewPresentation.copyISOButtonTitle, "复制 ISO")
        XCTAssertEqual(DateTimePreviewPresentation.copyUnixButtonTitle, "复制 Unix")
        XCTAssertEqual(DateTimePreviewPresentation.copyAllButtonTitle, "复制全部")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 45), "45 秒前")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 120), "2 分钟前")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 7_200), "2 小时前")
        XCTAssertEqual(DateTimePreviewPresentation.relativeTime(secondsAgo: 172_800), "2 天前")
    }

    func testFilePreviewLabelsAreLocalized() {
        XCTAssertEqual(FilePreviewPresentation.filesTitle(count: 3), "3 个文件")
        XCTAssertEqual(FilePreviewPresentation.missingSummary(count: 2), "2 个缺失")
        XCTAssertEqual(FilePreviewPresentation.missingBadge, "缺失")
        XCTAssertEqual(FilePreviewPresentation.detailsTitle, "文件详情")
        XCTAssertEqual(FilePreviewPresentation.openFileButtonTitle, "打开文件")
        XCTAssertEqual(FilePreviewPresentation.revealInFinderButtonTitle, "在 Finder 中显示")
        XCTAssertEqual(FilePreviewPresentation.copyPathButtonTitle, "复制路径")
        XCTAssertEqual(FilePreviewPresentation.copyNameButtonTitle, "复制名称")
        XCTAssertEqual(FilePreviewPresentation.fileDoesNotExistMessage, "文件不存在")
    }

    func testTextSummaryLabelsAreLocalized() {
        XCTAssertEqual(TextSummaryPresentation.wordsLabel, "词数")
        XCTAssertEqual(TextSummaryPresentation.charactersLabel, "字符")
        XCTAssertEqual(TextSummaryPresentation.linesLabel, "行数")
        XCTAssertEqual(TextSummaryPresentation.paragraphsLabel, "段落")
        XCTAssertEqual(TextSummaryPresentation.summaryTitle, "摘要")
        XCTAssertEqual(TextSummaryPresentation.keywordsTitle, "关键词")
        XCTAssertEqual(TextSummaryPresentation.generateSummaryButtonTitle, "生成摘要")
        XCTAssertEqual(TextSummaryPresentation.showSummaryTitle, "显示摘要")
        XCTAssertEqual(TextSummaryPresentation.showFullTextTitle, "显示全文")
        XCTAssertEqual(TextSummaryPresentation.loadingMoreParagraphsTitle, "加载更多段落...")
    }

    func testTextToolLabelsAreLocalized() {
        XCTAssertEqual(TextToolsPresentation.uppercaseButtonTitle, "转大写")
        XCTAssertEqual(TextToolsPresentation.lowercaseButtonTitle, "转小写")
        XCTAssertEqual(TextToolsPresentation.cleanupWhitespaceButtonTitle, "清理空白")
    }
}
