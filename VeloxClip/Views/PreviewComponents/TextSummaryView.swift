import SwiftUI
import AppKit
import Foundation

// Text summary view
struct TextSummaryView: View {
    let text: String
    @State private var summary: String?
    @State private var keywords: [String] = []
    @State private var showFullText = false
    @State private var isGeneratingSummary = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Statistics
            HStack(spacing: 16) {
                StatItem(icon: "text.word.spacing", label: "Words", value: "\(wordCount)")
                StatItem(icon: "textformat", label: "Characters", value: "\(text.count)")
                StatItem(icon: "line.3.horizontal", label: "Lines", value: "\(lineCount)")
                StatItem(icon: "paragraph", label: "Paragraphs", value: "\(paragraphCount)")
            }
            .padding(12)
            .background(Color(white: 0.95))
            .cornerRadius(8)
            
            // Summary section
            if let summary = summary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Summary")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: { copyText(summary) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Color(white: 0.95))
                .cornerRadius(8)
            } else if isGeneratingSummary {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating summary...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
            } else if text.count > 200 {
                Button(action: generateSummary) {
                    Label("Generate Summary", systemImage: "text.alignleft")
                }
                .buttonStyle(.bordered)
            }
            
            // Keywords
            if !keywords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keywords")
                        .font(.headline)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(keywords, id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(12)
                .background(Color(white: 0.95))
                .cornerRadius(8)
            }
            
            // Full text toggle
            if text.count > 500 {
                Button(action: { showFullText.toggle() }) {
                    Label(showFullText ? "Show Summary" : "Show Full Text", systemImage: showFullText ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
            }
            
            // Text content
            if showFullText {
                ScrollView {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .padding(12)
                .background(Color(white: 0.95))
                .cornerRadius(8)
            } else {
                ScrollView {
                    Text(text.prefix(500) + (text.count > 500 ? "..." : ""))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .padding(12)
                .background(Color(white: 0.95))
                .cornerRadius(8)
            }
        }
        .task {
            await extractKeywordsAsync()
        }
    }
    
    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    private var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }
    
    private var paragraphCount: Int {
        text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
    
    private func generateSummary() {
        isGeneratingSummary = true
        
        Task { @MainActor in
            // Use AI service to generate summary
            do {
                let result = try await LLMService.shared.performAction(.summarize, content: text)
                summary = result
                isGeneratingSummary = false
            } catch {
                // Fallback to simple summary
                summary = generateSimpleSummary()
                isGeneratingSummary = false
            }
        }
    }
    
    private func generateSimpleSummary() -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let summaryLength = min(3, sentences.count)
        return sentences.prefix(summaryLength).joined(separator: ". ") + "."
    }
    
    private func extractKeywordsAsync() async {
        // Simple keyword extraction - find most common words (async to avoid blocking UI)
        await Task.detached(priority: .userInitiated) {
            let words = text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
            
            var wordCounts: [String: Int] = [:]
            for word in words {
                wordCounts[word, default: 0] += 1
            }
            
            let extractedKeywords = Array(wordCounts.sorted { $0.value > $1.value }
                .prefix(10)
                .map { $0.key })
            
            await MainActor.run {
                keywords = extractedKeywords
            }
        }.value
    }
    
    private func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// Flow layout for keywords
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

