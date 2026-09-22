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
    /// Splits a document for incremental rendering WITHOUT changing what it is.
    ///
    /// Three rules earn their keep: fence lines are re-emitted (dropping them
    /// handed the renderer bare prose, so no code block could ever be styled),
    /// a blank line inside an open list does not split it (each fragment would
    /// become its own document and restart numbering), and CRLF is normalised
    /// first (`.newlines` treats CR and LF as separate separators, which
    /// injected a blank line between every line of Windows-copied text).
    nonisolated static func chunk(_ input: String) -> [MarkdownChunk] {
        // Normalise line endings once: splitting on `.newlines` made every
        // CRLF line yield the line plus an empty string.
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var chunks: [MarkdownChunk] = []
        let lines = normalized.components(separatedBy: "\n")
        var currentChunk = ""
        var inCodeBlock = false
        // Which character opened the block: ``` and ~~~ do not close each other.
        var fenceCharacter: Character = "`"
        // Tracked rather than re-derived — re-splitting the whole buffer on
        // every blank line made a loose list quadratic (8s for 4000 items).
        var lastNonEmptyLine = ""
        // A blank line inside a list only holds the chunk open if a list item
        // or an indented continuation actually follows it.
        var pendingBlankLines = 0

        func flush() {
            let trimmed = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(MarkdownChunk(content: trimmed)) }
            currentChunk = ""
            lastNonEmptyLine = ""
            pendingBlankLines = 0
        }

        func isFence(_ trimmed: String) -> Bool {
            trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
        }

        /// A list marker at the START of a line: `-`, `*`, `+`, or `N.` with at
        /// most nine digits (CommonMark's limit). Prose that merely begins with
        /// a year — "1984. It was a bright cold day" — is not a list item, so
        /// the caller must also know the line begins a list.
        func looksLikeAListItem(_ trimmed: String) -> Bool {
            if trimmed == "-" || trimmed == "*" || trimmed == "+" { return false }
            for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) { return true }
            let digits = trimmed.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9 else { return false }
            let rest = trimmed.dropFirst(digits.count)
            return rest.hasPrefix(". ") || rest.hasPrefix(") ")
        }

        /// Indented continuation of a list item (a nested list or a paragraph
        /// belonging to the item above).
        func isIndentedContinuation(_ line: String) -> Bool {
            line.hasPrefix("  ") || line.hasPrefix("\t")
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isFence(trimmed) {
                if inCodeBlock {
                    // Only the character that opened the block can close it.
                    if trimmed.first == fenceCharacter {
                        currentChunk += line + "\n"
                        flush()
                        inCodeBlock = false
                    } else {
                        currentChunk += line + "\n"
                    }
                } else {
                    flush()
                    currentChunk = line + "\n"
                    inCodeBlock = true
                    fenceCharacter = trimmed.first ?? "`"
                }
                continue
            }

            if inCodeBlock {
                currentChunk += line + "\n"
                continue
            }

            if trimmed.hasPrefix("#") {
                flush()
                chunks.append(MarkdownChunk(content: line))
                continue
            }

            if trimmed.isEmpty {
                // Defer the decision: whether this blank line splits depends on
                // what comes next.
                if currentChunk.isEmpty {
                    continue
                }
                if looksLikeAListItem(lastNonEmptyLine) || isIndentedContinuation(lastNonEmptyLine) {
                    pendingBlankLines += 1
                } else {
                    flush()
                }
                continue
            }

            // A non-blank line after a held-open blank line: keep the list
            // together only if this line continues it.
            if pendingBlankLines > 0 {
                if looksLikeAListItem(trimmed) || isIndentedContinuation(line) {
                    currentChunk += String(repeating: "\n", count: pendingBlankLines)
                    pendingBlankLines = 0
                } else {
                    flush()
                }
            }

            currentChunk += line + "\n"
            lastNonEmptyLine = trimmed
            _ = index
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
