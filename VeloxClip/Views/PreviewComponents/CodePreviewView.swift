import SwiftUI
import AppKit

// Code preview with syntax highlighting
struct CodePreviewView: View {
    let code: String
    @State private var detectedLanguage: String = "Plain Text"
    @State private var showLineNumbers = true
    @State private var fontSize: CGFloat = 13
    
    
    // Static shared cache to persist results between item switches
    private static var globalHighlightCache: [String: AttributedString] = [:]
    private static let maxCacheEntries = 2000
    
    // Pre-compiled keyword regexes for performance
    static let keywordRegexes: [String: NSRegularExpression] = {
        var regexes: [String: NSRegularExpression] = [:]
        for (lang, keywords) in languageKeywords {
            let pattern = "\\b(\(keywords.joined(separator: "|")))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                regexes[lang] = regex
            }
        }
        return regexes
    }()
    
    
    static let languageKeywords: [String: [String]] = [
        "Swift": ["func", "class", "struct", "enum", "var", "let", "import", "extension", "protocol", "if", "else", "for", "while", "switch", "case", "return", "guard", "try", "catch", "async", "await"],
        "Python": ["def", "class", "import", "from", "if", "else", "elif", "for", "while", "try", "except", "return", "yield", "async", "await"],
        "JavaScript": ["function", "const", "let", "var", "class", "import", "export", "if", "else", "for", "while", "try", "catch", "async", "await"],
        "TypeScript": ["function", "const", "let", "var", "class", "interface", "type", "import", "export", "if", "else", "for", "while", "try", "catch", "async", "await"],
        "Java": ["public", "private", "class", "interface", "import", "package", "static", "void", "if", "else", "for", "while", "try", "catch", "return"],
        "C++": ["#include", "using", "namespace", "class", "struct", "public", "private", "if", "else", "for", "while", "return", "int", "void", "bool"],
        "C": ["#include", "#define", "int", "void", "char", "if", "else", "for", "while", "return", "struct"],
        "Go": ["package", "import", "func", "var", "const", "type", "struct", "interface", "if", "else", "for", "range", "return"],
        "Rust": ["fn", "let", "mut", "struct", "enum", "impl", "trait", "use", "if", "else", "for", "while", "match", "return"],
        "HTML": ["<!DOCTYPE", "<html", "<head", "<body", "<div", "<span", "<p", "<a", "<img", "<script", "<style"],
        "CSS": ["@media", "@keyframes", "@import", "body", "div", "class", "id", "color", "background", "margin", "padding"],
        "SQL": ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "TABLE", "JOIN", "GROUP", "ORDER", "BY"],
        "Shell": ["#!/bin", "echo", "if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "export", "rm", "cp", "mv", "mkdir", "sudo", "chmod", "chown", "ls", "grep", "cat", "ssh", "git", "npm", "yarn", "docker", "brew", "apt"],
        "YAML": ["---", "apiVersion", "kind", "metadata", "spec", "name", "type", "key", "value"],
        "JSON": ["true", "false", "null"]
    ]
    
    // Pre-compiled regexes for performance
    static let stringRegex = try? NSRegularExpression(pattern: #""[^"]*"|'[^']*'"#, options: [])
    static let numberRegex = try? NSRegularExpression(pattern: #"\b\d+\.?\d*\b"#, options: [])
    static let commentRegexes = [
        try? NSRegularExpression(pattern: #"//.*"#, options: []),
        try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#, options: []),
        try? NSRegularExpression(pattern: #"#.*"#, options: [])
    ].compactMap { $0 }
    
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                toolbar.padding(.horizontal, 16)
                codeScrollView(availableWidth: geo.size.width)
            }
        }
        .onAppear {
            detectLanguage()
        }
        .onChange(of: detectedLanguage) { _, _ in Self.globalHighlightCache.removeAll() }
        .onChange(of: fontSize) { _, _ in Self.globalHighlightCache.removeAll() }
        .onChange(of: code) { _, _ in
            detectLanguage()
        }
    }
    
    private var toolbar: some View {
        HStack {
            Picker("Language", selection: $detectedLanguage) {
                ForEach(availableLanguages, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu).frame(width: 150)
            
            Toggle("Line Numbers", isOn: $showLineNumbers).toggleStyle(.switch).controlSize(.small)
            
            HStack(spacing: 8) {
                Button(action: { fontSize = max(10, fontSize - 1) }) { Image(systemName: "minus") }
                .buttonStyle(.plain)
                Text("\(Int(fontSize))pt").font(.caption).foregroundColor(.secondary).frame(width: 40)
                Button(action: { fontSize = min(20, fontSize + 1) }) { Image(systemName: "plus") }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Button("Format", action: formatCode).buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.bottom, 4)
    }
    
    private func codeLines(for codeString: String) -> [String] {
        codeString.components(separatedBy: .newlines)
    }
    
    private var availableLanguages: [String] {
        ["Plain Text"] + Self.languageKeywords.keys.sorted()
    }

    private func codeScrollView(availableWidth: CGFloat) -> some View {
        let lines = codeLines(for: code)
        // Calculate a fixed width for the line number column based on total lines
        let maxLineNumberWidth: CGFloat = CGFloat(String(lines.count).count) * 9 + 16
        
        return ScrollView([.horizontal, .vertical], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 0) {
                        if showLineNumbers {
                            lineNumberCell(index: index, width: maxLineNumberWidth)
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 1)
                        }
                        
                        codeCell(line: line)
                    }
                }
            }
            .padding(.vertical, 12)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: availableWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    @ViewBuilder
    private func lineNumberCell(index: Int, width: CGFloat) -> some View {
        Text("\(index + 1)")
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.4))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(width: width, alignment: .trailing)
            .background(Color.secondary.opacity(0.05))
    }
    
    @ViewBuilder
    private func codeCell(line: String) -> some View {
        highlightCode(line: line, language: detectedLanguage)
            .font(.system(size: fontSize, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 2)
            .padding(.leading, 6)
            .padding(.trailing, 30)
    }


    private func detectLanguage() {
        let lower = code.lowercased()
        var bestMatch: (lang: String, score: Int) = ("Plain Text", 0)
        
        for (lang, keywords) in Self.languageKeywords {
            let score = keywords.filter { lower.contains($0.lowercased()) }.count
            if score > bestMatch.score { bestMatch = (lang, score) }
        }
        
        if bestMatch.score > 0 {
            detectedLanguage = bestMatch.lang
        } else {
            // Fallback rules
            let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                detectedLanguage = "JSON"
            } else if lower.contains("<!doctype") || (lower.contains("<html") && lower.contains("</html>")) {
                detectedLanguage = "HTML"
            } else if lower.contains("body {") || lower.contains(".class {") {
                detectedLanguage = "CSS"
            } else if lower.hasPrefix("./") || lower.hasPrefix("/") || lower.contains("rm -rf") || lower.contains("sudo ") || lower.contains("build") {
                detectedLanguage = "Shell"
            } else {
                detectedLanguage = "Plain Text"
            }
        }
    }
    
    @ViewBuilder
    private func highlightCode(line: String, language: String) -> some View {
        if language == "Plain Text" || line.count > 500 { // Skip highlighting for very long lines
            Text(line).foregroundColor(.primary)
        } else {
            getCachedOrHighlightedText(line: line, language: language)
        }
    }
    
    private func getCachedOrHighlightedText(line: String, language: String) -> Text {
        let cacheKey = "\(language):\(fontSize):\(line)"
        if let cached = Self.globalHighlightCache[cacheKey] {
            return Text(cached)
        } else {
            let highlighted = highlightSyntax(line: line, language: language)
            if Self.globalHighlightCache.count >= Self.maxCacheEntries {
                // Simple eviction
                _ = Self.globalHighlightCache.removeValue(forKey: Self.globalHighlightCache.keys.first!)
            }
            Self.globalHighlightCache[cacheKey] = highlighted
            return Text(highlighted)
        }
    }
    
    private func highlightSyntax(line: String, language: String) -> AttributedString {
        var attr = AttributedString(line)
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        
        // Helper to apply style
        func style(_ range: NSRange, color: Color, bold: Bool = false, italic: Bool = false) {
            guard let r = Range(range, in: line),
                  let start = attr.characters.index(attr.startIndex, offsetBy: line.distance(from: line.startIndex, to: r.lowerBound), limitedBy: attr.endIndex),
                  let end = attr.characters.index(attr.startIndex, offsetBy: line.distance(from: line.startIndex, to: r.upperBound), limitedBy: attr.endIndex) else { return }
            
            let targetRange = start..<end
            attr[targetRange].foregroundColor = color
            if bold { attr[targetRange].font = .system(size: fontSize, design: .monospaced).bold() }
            if italic { attr[targetRange].font = .system(size: fontSize, design: .monospaced).italic() }
        }
        
        // 1. Keywords (Using pre-compiled composite regex)
        if let regex = Self.keywordRegexes[language] {
            regex.enumerateMatches(in: line, range: fullRange) { match, _, _ in
                if let m = match { style(m.range, color: .blue, bold: true) }
            }
        }
        
        // 2. Strings
        Self.stringRegex?.enumerateMatches(in: line, range: fullRange) { match, _, _ in
            if let m = match { style(m.range, color: .green) }
        }
        
        // 3. Numbers
        Self.numberRegex?.enumerateMatches(in: line, range: fullRange) { match, _, _ in
            if let m = match { style(m.range, color: .orange) }
        }
        
        // 4. Comments
        for regex in Self.commentRegexes {
            regex.enumerateMatches(in: line, range: fullRange) { match, _, _ in
                if let m = match { style(m.range, color: .gray, italic: true) }
            }
        }
        
        return attr
    }
    
    private func formatCode() {
        let lines = code.components(separatedBy: .newlines)
        var formatted: [String] = []
        var indent = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { formatted.append(""); continue }
            if trimmed.hasSuffix("}") || trimmed.hasSuffix("]") { indent = max(0, indent - 1) }
            formatted.append(String(repeating: "    ", count: indent) + trimmed)
            if trimmed.hasSuffix("{") || trimmed.hasSuffix("[") { indent += 1 }
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted.joined(separator: "\n"), forType: .string)
    }
}


