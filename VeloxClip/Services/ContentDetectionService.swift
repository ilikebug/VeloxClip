import Foundation

enum DetectedContentType: String, Sendable {
    case url, json, table, datetime, code, longtext, markdown, plain, image, color, file
}

actor ContentDetectionService {
    static let shared = ContentDetectionService()
    
    private var cache: [UUID: DetectedContentType] = [:]
    private let maxCacheSize = 500
    
    func detectType(for item: ClipboardItem) async -> DetectedContentType {
        if let cached = cache[item.id] {
            return cached
        }
        
        let type = performDetection(for: item)
        
        if cache.count >= maxCacheSize {
            cache.removeValue(forKey: cache.keys.first!)
        }
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
        if isLongText(content) { return .longtext }
        if isMarkdown(content) { return .markdown }
        
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
        let firstLine = lines[0]
        return firstLine.contains(",") || firstLine.contains("\t") || firstLine.contains("|")
    }
    
    private func isDateTime(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count < 30 && (trimmed.contains("-") || trimmed.contains("/")) // Simple check
    }
    
    private func isLongText(_ content: String) -> Bool {
        return content.count > 500
    }
    
    private func isMarkdown(_ content: String) -> Bool {
        return content.contains("# ") || content.contains("**") || content.contains("](")
    }
    
    func clearCache() {
        cache.removeAll()
    }
}
