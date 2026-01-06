import SwiftUI
import AppKit

// Code preview with syntax highlighting
struct CodePreviewView: View {
    let code: String
    @State private var detectedLanguage: String = "Plain Text"
    @State private var showLineNumbers = true
    @State private var fontSize: CGFloat = 13
    
    private let languageKeywords: [String: [String]] = [
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
        "Shell": ["#!/bin", "echo", "if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "export"],
        "YAML": ["---", "apiVersion", "kind", "metadata", "spec", "name", "type", "key", "value"],
        "JSON": ["{", "}", "[", "]", "\"", ":", ","]
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toolbar
            HStack {
                Picker("Language", selection: $detectedLanguage) {
                    ForEach(availableLanguages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                Toggle("Line Numbers", isOn: $showLineNumbers)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                
                HStack(spacing: 8) {
                    Button(action: { fontSize = max(10, fontSize - 1) }) {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(Int(fontSize))pt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                    
                    Button(action: { fontSize = min(20, fontSize + 1) }) {
                        Image(systemName: "textformat.size.larger")
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button(action: formatCode) {
                    Label("Format", systemImage: "text.alignleft")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 8)
            
            // Code display
            ScrollView(.horizontal, showsIndicators: true) {
                ScrollView(.vertical, showsIndicators: true) {
                    if showLineNumbers {
                        codeWithLineNumbers
                    } else {
                        codeWithoutLineNumbers
                    }
                }
            }
            .frame(maxHeight: 400)
            .background(Color(white: 0.95))
            .cornerRadius(8)
        }
        .onAppear {
            detectLanguage()
        }
    }
    
    private var codeWithLineNumbers: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line numbers
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(codeLines.enumerated()), id: \.offset) { index, _ in
                    Text("\(index + 1)")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                        .padding(.trailing, 12)
                        .padding(.vertical, 2)
                }
            }
            .background(Color(white: 0.9))
            
            // Code content
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(codeLines.enumerated()), id: \.offset) { index, line in
                    highlightCode(line: line, language: detectedLanguage)
                        .font(.system(size: fontSize, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    private var codeWithoutLineNumbers: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(codeLines.enumerated()), id: \.offset) { index, line in
                highlightCode(line: line, language: detectedLanguage)
                    .font(.system(size: fontSize, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
        .padding(12)
    }
    
    private var codeLines: [String] {
        code.components(separatedBy: .newlines)
    }
    
    private var availableLanguages: [String] {
        ["Plain Text", "Swift", "Python", "JavaScript", "TypeScript", "Java", "C++", "C", "Go", "Rust", "HTML", "CSS", "SQL", "Shell", "YAML", "JSON"]
    }
    
    private func detectLanguage() {
        let lowercasedCode = code.lowercased()
        var scores: [String: Int] = [:]
        
        for (lang, keywords) in languageKeywords {
            var score = 0
            for keyword in keywords {
                if lowercasedCode.contains(keyword.lowercased()) {
                    score += 1
                }
            }
            scores[lang] = score
        }
        
        if let bestMatch = scores.max(by: { $0.value < $1.value }), bestMatch.value > 0 {
            detectedLanguage = bestMatch.key
        } else {
            // Try to detect by file extension patterns or common patterns
            if code.trimmingCharacters(in: .whitespaces).hasPrefix("{") || code.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                detectedLanguage = "JSON"
            } else if code.contains("<!DOCTYPE") || code.contains("<html") {
                detectedLanguage = "HTML"
            } else {
                detectedLanguage = "Plain Text"
            }
        }
    }
    
    @ViewBuilder
    private func highlightCode(line: String, language: String) -> some View {
        if language == "Plain Text" {
            Text(line)
                .foregroundColor(.primary)
        } else {
            highlightSyntax(line: line, language: language)
        }
    }
    
    private func highlightSyntax(line: String, language: String) -> some View {
        let keywords = languageKeywords[language] ?? []
        var attributedString = AttributedString(line)
        
        // Helper function to apply attributes to a range
        func applyAttributes(to range: Range<String.Index>, foregroundColor: Color? = nil, font: Font? = nil) {
            // Convert String.Index range to AttributedString.Index range
            // Use String's character distance
            let startOffset = line.distance(from: line.startIndex, to: range.lowerBound)
            let endOffset = line.distance(from: line.startIndex, to: range.upperBound)
            
            guard startOffset >= 0 && endOffset <= attributedString.characters.count && endOffset >= startOffset else { return }
            
            let startIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: startOffset)
            let endIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: endOffset)
            let attrRange = startIndex..<endIndex
            
            if let color = foregroundColor {
                attributedString[attrRange].foregroundColor = color
            }
            if let font = font {
                attributedString[attrRange].font = font
            }
        }
        
        // Highlight keywords
        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
                
                for match in matches.reversed() {
                    if let range = Range(match.range, in: line) {
                        applyAttributes(to: range, foregroundColor: .blue, font: .system(size: fontSize, design: .monospaced).bold())
                    }
                }
            }
        }
        
        // Highlight strings
        let stringPattern = #""[^"]*"|'[^']*'"#
        if let regex = try? NSRegularExpression(pattern: stringPattern, options: []) {
            let nsString = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: line) {
                    applyAttributes(to: range, foregroundColor: .green)
                }
            }
        }
        
        // Highlight numbers
        let numberPattern = #"\b\d+\.?\d*\b"#
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let nsString = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: line) {
                    applyAttributes(to: range, foregroundColor: .orange)
                }
            }
        }
        
        // Highlight comments
        let commentPatterns = [
            #"//.*"#,           // Single line comments
            #"/\*[\s\S]*?\*/"#, // Multi-line comments
            #"#.*"#              // Shell/Python comments
        ]
        
        for pattern in commentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
                
                for match in matches.reversed() {
                    if let range = Range(match.range, in: line) {
                        applyAttributes(to: range, foregroundColor: .gray, font: .system(size: fontSize, design: .monospaced).italic())
                    }
                }
            }
        }
        
        return Text(attributedString)
    }
    
    private func formatCode() {
        // Basic formatting - indent code
        // This is a simple implementation, could be enhanced with proper formatters
        let lines = code.components(separatedBy: .newlines)
        var formatted: [String] = []
        var indentLevel = 0
        let indentString = "    "
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                formatted.append("")
                continue
            }
            
            // Decrease indent for closing braces
            if trimmed.hasSuffix("}") || trimmed.hasSuffix("]") {
                indentLevel = max(0, indentLevel - 1)
            }
            
            formatted.append(String(repeating: indentString, count: indentLevel) + trimmed)
            
            // Increase indent for opening braces
            if trimmed.hasSuffix("{") || trimmed.hasSuffix("[") {
                indentLevel += 1
            }
        }
        
        // Copy formatted code to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formatted.joined(separator: "\n"), forType: .string)
    }
}

