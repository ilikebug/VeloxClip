import Foundation

enum DetectedContentType: String, Sendable {
    case url, json, table, datetime, code, longtext, markdown, plain, image, color, file
}

actor ContentDetectionService {
    static let shared = ContentDetectionService()
    
    private var cache = FIFOCache<UUID, DetectedContentType>(maxEntries: 500)

    func detectType(for item: ClipboardItem) async -> DetectedContentType {
        if let cached = cache[item.id] {
            return cached
        }

        let type = performDetection(for: item)
        cache[item.id] = type

        return type
    }
    
    private func performDetection(for item: ClipboardItem) -> DetectedContentType {
        if item.type == "image" { return .image }
        if item.type == "color" { return .color }
        if item.type == "file" { return .file }
        
        guard let content = item.content, !content.isEmpty else { return .plain }
        
        if isURL(content) { return .url }
        if isJSON(content) { return .json }
        if isTableData(content) { return .table }
        if isDateTime(content) { return .datetime }
        if isCode(content) { return .code }
        if isMarkdown(content) { return .markdown }
        if isLongText(content) { return .longtext }
        
        return .plain
    }
    
    private func isJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else { return false }
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
    
    private func isURL(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.components(separatedBy: .newlines).count == 1 else { return false }
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://")
    }
    
    private func isCode(_ content: String) -> Bool {
        let codeIndicators = ["func ", "class ", "def ", "import ", "const ", "let ", "var ", "function ", "=>", "->", "public ", "private "]
        return codeIndicators.filter { content.contains($0) }.count >= 2
    }
    
    private func isTableData(_ content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return false }

        // Real tabular data has the same delimiter count on every row.
        // Comma and pipe content require >= 3 columns; otherwise short notes like
        // "状态 | 说明" can look like tables and show the table toolbar.
        for delimiter in ["\t", "|", ","] {
            let counts = lines.map { $0.components(separatedBy: delimiter).count - 1 }
            guard let first = counts.first, first >= 1, counts.allSatisfy({ $0 == first }) else { continue }
            if (delimiter == "," || delimiter == "|") && first < 2 { continue }
            return true
        }
        return false
    }

    private func isDateTime(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40 else { return false }

        // Strict full-string matches only — "my-branch-name" or "a/b/c" must not qualify
        let patterns = [
            #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}([ T]\d{1,2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?)?$"#, // 2026-06-12, ISO 8601
            #"^\d{1,2}[-/]\d{1,2}[-/]\d{2,4}$"#,   // 12/06/2026
            #"^\d{1,2}:\d{2}(:\d{2})?$"#,           // 14:30, 14:30:05
            #"^\d{10}$"#,                            // unix timestamp (seconds)
            #"^\d{13}$"#                             // unix timestamp (milliseconds)
        ]
        return patterns.contains { trimmed.range(of: $0, options: .regularExpression) != nil }
    }
    
    private func isLongText(_ content: String) -> Bool {
        return content.count > 500
    }
    
    private func isMarkdown(_ content: String) -> Bool {
        // Check for markdown headers (must be at start of line)
        let lines = content.components(separatedBy: .newlines)
        let hasHeader = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || 
                   trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") ||
                   trimmed.hasPrefix("##### ") || trimmed.hasPrefix("###### ")
        }
        
        // Check for other markdown indicators
        let hasBold = content.contains("**") && content.components(separatedBy: "**").count > 2
        let hasLinks = content.contains("](") || content.contains("![")
        let hasCodeBlock = content.contains("```")
        let hasBlockquote = lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
        let hasList = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                return true
            }
            // Check for numbered list (1. 2. etc.)
            if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                return true
            }
            return false
        }
        let hasTable = content.contains("|") && lines.filter { $0.contains("|") }.count >= 2
        
        // Markdown if it has header, or multiple other indicators
        let indicatorCount = [hasBold, hasLinks, hasCodeBlock, hasBlockquote, hasList, hasTable].filter { $0 }.count
        return hasHeader || indicatorCount >= 2
    }
    
    func clearCache() {
        cache.removeAll()
    }
}
