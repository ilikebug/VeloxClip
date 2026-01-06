import SwiftUI
import MarkdownUI

// Markdown chunk structure for lazy loading
struct MarkdownChunk: Identifiable {
    let id: UUID = UUID()
    let content: String
    let type: ChunkType
    
    enum ChunkType {
        case paragraph
        case codeBlock
        case heading
        case list
        case blockquote
    }
}

struct MarkdownView: View {
    let markdown: String
    
    // Lazy loading state
    @State private var allChunks: [MarkdownChunk] = []
    @State private var loadedChunks: [MarkdownChunk] = []
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var isLoadingMore = false
    
    // Static cache for parsed chunks to persist across view updates
    static var chunksCache: [String: [MarkdownChunk]] = [:]
    
    private let chunksPerPage = 20
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(loadedChunks) { chunk in
                    MarkdownChunkView(chunk: chunk)
                }
                
                if loadedChunks.count < allChunks.count {
                    loadMoreTrigger
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .textSelection(.enabled)
        .task(id: markdown) {
            await parseChunksAsync()
        }
    }
    
    private var loadMoreTrigger: some View {
        loadMoreIndicator.onAppear { loadMoreWithDebounce() }
    }
    
    private var loadMoreIndicator: some View {
        HStack {
            if isLoadingMore {
                ProgressView().scaleEffect(0.7)
                Text("Loading more...").font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
    
    private func parseChunksAsync() async {
        let input = markdown
        if let cached = Self.chunksCache[input] {
            allChunks = cached
            loadInitialChunks(from: cached)
            return
        }
        
        await Task.detached(priority: .userInitiated) {
            var chunks: [MarkdownChunk] = []
            let lines = input.components(separatedBy: .newlines)
            var currentChunk = ""
            var inCodeBlock = false
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                if trimmed.hasPrefix("```") {
                    if inCodeBlock {
                        if !currentChunk.isEmpty { chunks.append(MarkdownChunk(content: currentChunk, type: .codeBlock)) }
                        currentChunk = ""
                        inCodeBlock = false
                    } else {
                        if !currentChunk.isEmpty { chunks.append(MarkdownChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), type: .paragraph)) }
                        currentChunk = ""
                        inCodeBlock = true
                    }
                    continue
                }
                
                if inCodeBlock {
                    currentChunk += line + "\n"
                } else {
                    if trimmed.hasPrefix("#") {
                        if !currentChunk.isEmpty { chunks.append(MarkdownChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), type: .paragraph)) }
                        chunks.append(MarkdownChunk(content: line, type: .heading))
                        currentChunk = ""
                    } else if trimmed.isEmpty {
                        if !currentChunk.isEmpty {
                            let type: MarkdownChunk.ChunkType = currentChunk.contains(">") ? .blockquote : (currentChunk.contains("-") || currentChunk.contains("*") ? .list : .paragraph)
                            chunks.append(MarkdownChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), type: type))
                            currentChunk = ""
                        }
                    } else {
                        currentChunk += line + "\n"
                    }
                }
            }
            
            if !currentChunk.isEmpty {
                chunks.append(MarkdownChunk(content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), type: inCodeBlock ? .codeBlock : .paragraph))
            }
            
            if chunks.isEmpty { chunks.append(MarkdownChunk(content: input, type: .paragraph)) }
            
            await MainActor.run {
                if Self.chunksCache.count >= 100 {
                    Self.chunksCache.removeValue(forKey: Self.chunksCache.keys.first!)
                }
                Self.chunksCache[input] = chunks
                self.allChunks = chunks
                self.loadInitialChunks(from: chunks)
            }
        }.value
    }
    
    private func loadInitialChunks(from chunks: [MarkdownChunk]) {
        let initialCount = min(chunksPerPage, chunks.count)
        loadedChunks = Array(chunks.prefix(initialCount))
    }
    
    private func loadMoreWithDebounce() {
        guard !isLoadingMore && loadedChunks.count < allChunks.count else { return }
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            isLoadingMore = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                let nextCount = min(loadedChunks.count + chunksPerPage, allChunks.count)
                loadedChunks = Array(allChunks.prefix(nextCount))
                isLoadingMore = false
            }
        }
    }
}

// Individual chunk view with all styling
struct MarkdownChunkView: View {
    let chunk: MarkdownChunk
    
    var body: some View {
        Markdown(chunk.content)
            .markdownTextStyle(\.text) {
                FontSize(.em(1))
                ForegroundColor(.primary)
            }
            .markdownTextStyle(\.strong) {
                FontWeight(.semibold)
            }
            .markdownTextStyle(\.emphasis) {
                FontStyle(.italic)
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.96))
                ForegroundColor(.secondary)
                BackgroundColor(.secondary.opacity(0.1))
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                configuration.label
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                    }
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 4)
                    configuration.label
                        .padding(.leading, 12)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(2.0))
                        FontWeight(.bold)
                    }
                    .font(.largeTitle.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.75))
                        FontWeight(.bold)
                    }
                    .font(.title.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.5))
                        FontWeight(.bold)
                    }
                    .font(.title2.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading4) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.25))
                        FontWeight(.bold)
                    }
                    .font(.title3.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading5) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.1))
                        FontWeight(.bold)
                    }
                    .font(.headline.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading6) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.0))
                        FontWeight(.bold)
                    }
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .padding(.vertical, 2)
            }
            .markdownBlockStyle(\.listItem) { configuration in
                configuration.label
                    .padding(.vertical, 2)
            }
            .markdownBlockStyle(\.thematicBreak) {
                Divider()
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

