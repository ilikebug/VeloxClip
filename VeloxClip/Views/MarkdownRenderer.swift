import SwiftUI

struct MarkdownView: View {
    let markdown: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(markdown), id: \.id) { block in
                renderBlock(block)
            }
        }
    }
    
    private func parseMarkdown(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            // Headers
            if let header = parseHeader(line) {
                blocks.append(header)
                i += 1
                continue
            }
            
            // Code blocks
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }
            
            // Blockquotes
            if line.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].hasPrefix("> ") {
                    quoteLines.append(String(lines[i].dropFirst(2)))
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }
            
            // Unordered lists
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var listItems: [String] = []
                while i < lines.count && (lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ")) {
                    listItems.append(String(lines[i].dropFirst(2)))
                    i += 1
                }
                blocks.append(.unorderedList(listItems))
                continue
            }
            
            // Ordered lists
            if let _ = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                var listItems: [String] = []
                while i < lines.count, let _ = lines[i].range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    let item = lines[i].replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                    listItems.append(item)
                    i += 1
                }
                blocks.append(.orderedList(listItems))
                continue
            }
            
            // Horizontal rule
            if line.trimmingCharacters(in: .whitespaces) == "---" || line.trimmingCharacters(in: .whitespaces) == "***" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }
            
            // Regular paragraph
            if !line.isEmpty {
                var paragraphLines: [String] = [line]
                i += 1
                while i < lines.count {
                    let nextLine = lines[i]
                    if nextLine.isEmpty || 
                       nextLine.hasPrefix("#") ||
                       nextLine.hasPrefix("```") ||
                       nextLine.hasPrefix("> ") ||
                       nextLine.hasPrefix("- ") ||
                       nextLine.hasPrefix("* ") ||
                       nextLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                        break
                    }
                    paragraphLines.append(nextLine)
                    i += 1
                }
                let paragraph = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                if !paragraph.isEmpty {
                    blocks.append(.paragraph(paragraph))
                }
            } else {
                i += 1
            }
        }
        
        return blocks
    }
    
    private func parseHeader(_ line: String) -> MarkdownBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            if level <= 6 {
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                return .header(level, text)
            }
        }
        return nil
    }
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .header(let level, let text):
            Text(parseInlineMarkdown(text))
                .font(headerFont(for: level))
                .fontWeight(.bold)
                .padding(.top, level == 1 ? 0 : 8)
                .padding(.bottom, 4)
        
        case .paragraph(let text):
            Text(parseInlineMarkdown(text))
                .font(.body)
                .padding(.vertical, 2)
        
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.vertical, 4)
        
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 4)
                Text(parseInlineMarkdown(text))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
            }
            .padding(.vertical, 4)
        
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(parseInlineMarkdown(item))
                            .font(.body)
                    }
                }
            }
            .padding(.vertical, 2)
        
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(parseInlineMarkdown(item))
                            .font(.body)
                    }
                }
            }
            .padding(.vertical, 2)
        
        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)
        }
    }
    
    private func headerFont(for level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        case 6: return .subheadline
        default: return .body
        }
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        // Use SwiftUI's built-in Markdown support for inline elements
        if let attributedString = try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributedString
        }
        // Fallback to plain text
        return AttributedString(text)
    }
}

enum MarkdownBlock: Identifiable {
    case header(Int, String) // level, text
    case paragraph(String)
    case codeBlock(String)
    case blockquote(String)
    case unorderedList([String])
    case orderedList([String])
    case horizontalRule
    
    var id: String {
        switch self {
        case .header(let level, let text):
            return "h\(level)-\(text.prefix(20))"
        case .paragraph(let text):
            return "p-\(text.prefix(20))"
        case .codeBlock(let code):
            return "code-\(code.prefix(20))"
        case .blockquote(let text):
            return "quote-\(text.prefix(20))"
        case .unorderedList(let items):
            return "ul-\(items.joined().prefix(20))"
        case .orderedList(let items):
            return "ol-\(items.joined().prefix(20))"
        case .horizontalRule:
            return "hr"
        }
    }
}

