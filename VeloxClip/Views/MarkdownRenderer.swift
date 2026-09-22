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
    // The key alone is the whole document — 100 × 400 KB pinned ~42 MB before
    // counting the parsed chunks.
    static var chunksCache = FIFOCache<String, [MarkdownChunk]>(
        maxEntries: 100,
        maxBytes: 16 * 1024 * 1024,
        sizeOf: { key, chunks in
            key.utf8.count + chunks.reduce(0) { $0 + $1.content.utf8.count }
        }
    )
    
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
        // …and how long the opening run was: per CommonMark only a run at least
        // that long closes it, so a ``` line inside a ```` block is content.
        var fenceLength = 0
        // Tracked rather than re-derived — re-splitting the whole buffer on
        // every blank line made a loose list quadratic (8s for 4000 items).
        var lastNonEmptyLine = ""
        // The raw line as well: lastNonEmptyLine is trimmed, so testing it for
        // indentation could never fire and the continuation rule was dead.
        var lastNonEmptyRawLine = ""
        // Whether the chunk currently HOLDS an open list. Testing only the
        // chunk's first line discarded the hold-open rule for every list with a
        // lead-in ("Here are the steps:"), which is most real lists; testing
        // the last line alone cannot tell "1) real first" from prose that
        // happens to begin "1) is also how the German ordinal is written".
        // A list item with a list above it in the same chunk is a real list.
        var chunkHasOpenList = false
        // A blank line inside a list only holds the chunk open if a list item
        // or an indented continuation actually follows it.
        var pendingBlankLines = 0

        // For each index, the longest run of each marker that appears at or
        // after it, so isOpeningFence is an array lookup rather than a scan of
        // the remaining document. The per-line scan was O(fences x lines) —
        // the same quadratic shape as the bug it replaced (34s on a 4000-line
        // document of descending dividers).
        func markerRun(_ trimmed: String) -> (marker: Character, length: Int, info: Substring)? {
            guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
            let run = trimmed.prefix { $0 == first }
            guard run.count >= 3 else { return nil }
            return (first, run.count, trimmed.dropFirst(run.count))
        }

        var maxBacktickCloserAfter = [Int](repeating: 0, count: lines.count + 1)
        var maxTildeCloserAfter = [Int](repeating: 0, count: lines.count + 1)
        for index in stride(from: lines.count - 1, through: 0, by: -1) {
            var backtick = maxBacktickCloserAfter[index + 1]
            var tilde = maxTildeCloserAfter[index + 1]
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            // Only a bare run can close a block, so only bare runs are indexed.
            if let run = markerRun(trimmed), run.info.trimmingCharacters(in: .whitespaces).isEmpty {
                if run.marker == "`" { backtick = max(backtick, run.length) }
                else { tilde = max(tilde, run.length) }
            }
            maxBacktickCloserAfter[index] = backtick
            maxTildeCloserAfter[index] = tilde
        }

        func flush() {
            let trimmed = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(MarkdownChunk(content: trimmed)) }
            currentChunk = ""
            lastNonEmptyLine = ""
            lastNonEmptyRawLine = ""
            chunkHasOpenList = false
            pendingBlankLines = 0
        }

        /// An opening fence: at least three of the same marker, and either a
        /// usable info string or a matching closer below. Without the second
        /// condition a run of tildes or backticks used as a visual divider
        /// opened a code block that swallowed the rest of the document.
        func isOpeningFence(_ trimmed: String, at index: Int) -> Bool {
            guard let run = markerRun(trimmed) else { return false }
            let info = run.info.trimmingCharacters(in: .whitespaces)
            if !info.isEmpty {
                // CommonMark forbids a backtick anywhere in a backtick fence's
                // info string, so "``` note ```" is a paragraph, not a fence.
                // A decorative tilde run is the same idea for "~~~ Section ~~~".
                let decorative = info.contains(run.marker)
                if !decorative { return true }
            }
            // Otherwise require a bare closer of at least this length below.
            let available = run.marker == "`"
                ? maxBacktickCloserAfter[min(index + 1, lines.count)]
                : maxTildeCloserAfter[min(index + 1, lines.count)]
            return available >= run.length
        }

        /// Per CommonMark: same marker, run at least as long as the opener, and
        /// no info string. Both the lookahead above and the branch that closes
        /// a block must agree, or a nested ```lang line ends the outer block
        /// and chunking stops being idempotent.
        func isClosingFence(_ trimmed: String) -> Bool {
            guard let run = markerRun(trimmed) else { return false }
            return run.marker == fenceCharacter
                && run.length >= fenceLength
                && run.info.trimmingCharacters(in: .whitespaces).isEmpty
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
            // CommonMark applies the same 9-digit limit to both delimiters; the
            // prose false positive ("section 12 subsection 3)") is rejected by
            // requiring a list ABOVE the line in the same chunk, not by capping
            // the digits — a cap broke real paren lists at item 100.
            return rest.hasPrefix(". ") || rest.hasPrefix(") ")
        }

        /// Indented continuation of a list item (a nested list or a paragraph
        /// belonging to the item above).
        func isIndentedContinuation(_ line: String) -> Bool {
            line.hasPrefix("  ") || line.hasPrefix("\t")
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCodeBlock {
                // Only a valid closer ends the block: a nested ```swift line
                // inside a ```` block is content, not a terminator.
                if isClosingFence(trimmed) {
                    currentChunk += line + "\n"
                    flush()
                    inCodeBlock = false
                    continue
                }
            } else if isOpeningFence(trimmed, at: index) {
                flush()
                currentChunk = line + "\n"
                inCodeBlock = true
                let run = markerRun(trimmed)
                fenceCharacter = run?.marker ?? "`"
                fenceLength = run?.length ?? 3
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
                if chunkHasOpenList,
                   looksLikeAListItem(lastNonEmptyLine) || isIndentedContinuation(lastNonEmptyRawLine) {
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

            // A list item opens a list — unless it directly follows a prose line
            // in the same chunk, which is what "…subsection 3) which applies /
            // 1) is also how the German ordinal is written" looks like. A real
            // list either starts its chunk, follows a lead-in that ends with
            // ":", or follows another list line or an indented continuation.
            if looksLikeAListItem(trimmed) {
                let followsList = looksLikeAListItem(lastNonEmptyLine)
                    || isIndentedContinuation(lastNonEmptyRawLine)
                let startsBlock = lastNonEmptyLine.isEmpty
                let followsLeadIn = lastNonEmptyLine.hasSuffix(":") || lastNonEmptyLine.hasSuffix("：")
                if followsList || startsBlock || followsLeadIn || chunkHasOpenList {
                    chunkHasOpenList = true
                }
            } else if !isIndentedContinuation(line) {
                chunkHasOpenList = false
            }
            currentChunk += line + "\n"
            lastNonEmptyLine = trimmed
            lastNonEmptyRawLine = line
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
