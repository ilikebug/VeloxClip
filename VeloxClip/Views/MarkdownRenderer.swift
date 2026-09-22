import SwiftUI
import MarkdownUI

// Markdown chunk structure for lazy loading — MarkdownUI classifies the
// content itself; chunking only exists so long documents render incrementally
struct MarkdownChunk: Identifiable {
    let id: UUID = UUID()
    let content: String
}

// Clipboard content is untrusted: never fetch remote images — an `![](https://…)`
// in copied text would otherwise beacon the user's IP the moment detail opens.
private struct NoRemoteImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View { EmptyView() }
}

private struct NoRemoteInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        throw URLError(.unsupportedURL)
    }
}

struct MarkdownView: View {
    let markdown: String
    @ObservedObject private var settings = AppSettings.shared

    // Lazy loading state
    @State private var allChunks: [MarkdownChunk] = []
    @State private var loadedChunks: [MarkdownChunk] = []
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var isLoadingMore = false
    
    // Static cache for parsed chunks to persist across view updates.
    // Cleared via CacheRegistry (see ViewCaches.registerAll) so CacheManager
    // does not have to name this view type.
    @MainActor
    static var chunksCache = FIFOCache<String, [MarkdownChunk]>(maxEntries: 100)
    
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
        .markdownImageProvider(NoRemoteImageProvider())
        .markdownInlineImageProvider(NoRemoteInlineImageProvider())
        // Links: same http(s)-only rule as everywhere else in the app
        .environment(\.openURL, OpenURLAction { url in
            WebURL.isOpenable(url) ? .systemAction : .handled
        })
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
                Text(L10n.string("preview.markdown.loadingMore", language: settings.appLanguage))
                    .font(.dsCaption)
                    .foregroundColor(.secondary)
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
            let chunks = MarkdownView.chunk(input)
            await MainActor.run {
                Self.chunksCache[input] = chunks
                self.allChunks = chunks
                self.loadInitialChunks(from: chunks)
            }
        }.value
    }

    /// Splits a document for incremental rendering WITHOUT changing what it is.
    ///
    /// Two rules earn their keep here: fence lines are re-emitted (dropping
    /// them handed the renderer bare prose, so no code block could ever be
    /// styled), and a blank line does not split a list (each fragment would
    /// become its own document and restart numbering).
    nonisolated static func chunk(_ input: String) -> [MarkdownChunk] {
        var chunks: [MarkdownChunk] = []
        let lines = input.components(separatedBy: .newlines)
        var currentChunk = ""
        var inCodeBlock = false

        func flush() {
            let trimmed = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(MarkdownChunk(content: trimmed)) }
            currentChunk = ""
        }

        /// True when the buffer is an open list, so a blank line inside it is
        /// loose-list spacing rather than a document boundary.
        func bufferIsAList() -> Bool {
            let lines = currentChunk
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let last = lines.last else { return false }
            if last.hasPrefix("- ") || last.hasPrefix("* ") || last.hasPrefix("+ ") { return true }
            let ordered = last.prefix { $0.isNumber }
            return !ordered.isEmpty && last.dropFirst(ordered.count).hasPrefix(". ")
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // Keep the closing fence with its block, then flush.
                    currentChunk += line + "\n"
                    flush()
                    inCodeBlock = false
                } else {
                    flush()
                    currentChunk = line + "\n"
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                currentChunk += line + "\n"
            } else if trimmed.hasPrefix("#") {
                flush()
                chunks.append(MarkdownChunk(content: line))
            } else if trimmed.isEmpty {
                // A blank line inside a list is loose-list spacing, not a break.
                if bufferIsAList() {
                    currentChunk += "\n"
                } else {
                    flush()
                }
            } else {
                currentChunk += line + "\n"
            }
        }

        flush()
        if chunks.isEmpty { chunks.append(MarkdownChunk(content: input)) }
        return chunks
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
                    .font(.dsLargeTitle.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.75))
                        FontWeight(.bold)
                    }
                    .font(.dsTitle.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.5))
                        FontWeight(.bold)
                    }
                    .font(.dsTitle2.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading4) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.25))
                        FontWeight(.bold)
                    }
                    .font(.dsTitle3.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading5) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.1))
                        FontWeight(.bold)
                    }
                    .font(.dsHeadline.bold())
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading6) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.0))
                        FontWeight(.bold)
                    }
                    .font(.dsSubheadline.bold())
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
