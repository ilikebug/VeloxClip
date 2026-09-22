import Foundation

// ---------------------------------------------------------------------------
// The markdown chunker: splits a text for incremental rendering without
// changing what the document IS — a list fragment must not restart its
// numbering, and code-block fences must reach the renderer.
//
// This was four iterations of in-place rewrite on a 131-line function body
// with six nested functions and two pre-computed arrays. Extracting it to a
// free function makes the state machine visible and the invariants testable.
// ---------------------------------------------------------------------------

enum Chunk {

    // ---- helpers ----------------------------------------------------------

    /// At least three of the same marker: ``` or ~~~.
    static func fenceRun(_ trimmed: String) -> (marker: Character, len: Int, info: String)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let runLen = trimmed.prefix { $0 == first }.count
        guard runLen >= 3 else { return nil }
        let info = String(trimmed.dropFirst(runLen)).trimmingCharacters(in: .whitespaces)
        return (first, runLen, info)
    }

    /// ```swift counts; ``` `` ` `` does not (backticks in info — decorative).
    static func isDecorativeRun(_ trimmed: String) -> Bool {
        guard let run = fenceRun(trimmed) else { return false }
        let info = run.info
        // CommonMark: backtick in backtick info string -> not a fence.
        // Same for tilde, so "~~~ Section ~~~" is a decorative heading.
        return info.contains(String(run.marker))
    }

    /// A list marker at START of line: "- ", "* ", "+ ", or up to 9-digit N. /N)
    /// CommonMark's 9-digit limit applies to both delimiters.
    static func isListItem(_ trimmed: String) -> Bool {
        if trimmed == "-" || trimmed == "*" || trimmed == "+" { return false }
        for m in ["- ", "* ", "+ "] where trimmed.hasPrefix(m) { return true }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return false }
        let rest = trimmed.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    /// Indented under a list item.
    static func isIndented(_ line: String) -> Bool {
        line.hasPrefix("  ") || line.hasPrefix("\t")
    }

    // ---- public -----------------------------------------------------------

    /// Splits a string into chunks suitable for lazy rendering.
    ///
    /// - Fences (``` and ~~~) keep their content together and re-emit their
    ///   delimiters so MarkdownUI can style them.
    /// - A blank line inside a loose list does NOT split it — numbering
    ///   would restart.
    /// - Prose paragraphs split on blank lines.
    /// - Divider runs without an info string OR a matching closer are prose,
    ///   not a code block that swallows the rest of the document.
    static func run(on text: String) -> [MarkdownChunk] {
        let norm = text.replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = norm.components(separatedBy: "\n")

        // Pre-compute, per index, the longest BARE closer seen at or after
        // that position. This replaces the per-line remainder scan that was
        // O(fences × lines) — 34s for 2000 descending dividers.
        var maxBacktickAfter = [Int](repeating: 0, count: rawLines.count + 1)
        var maxTildeAfter    = [Int](repeating: 0, count: rawLines.count + 1)
        for idx in stride(from: rawLines.count - 1, through: 0, by: -1) {
            var bb = maxBacktickAfter[idx + 1]
            var tt = maxTildeAfter[idx + 1]
            let t = rawLines[idx].trimmingCharacters(in: .whitespaces)
            // Only a BARE run can close a block.
            if let r = fenceRun(t), r.info.isEmpty {
                if r.marker == "`" { bb = max(bb, r.len) }
                else               { tt = max(tt, r.len) }
            }
            maxBacktickAfter[idx] = bb
            maxTildeAfter[idx]    = tt
        }

        func hasCloser(marker: Character, length: Int, after idx: Int) -> Bool {
            let avail = marker == "`"
                ? maxBacktickAfter[min(idx + 1, rawLines.count)]
                : maxTildeAfter[min(idx + 1, rawLines.count)]
            return avail >= length
        }

        /// Decorative run = no usable closer below AND no valid info string.
        func isDivider(_ trimmed: String, at idx: Int) -> Bool {
            guard let r = fenceRun(trimmed) else { return false }
            if isDecorativeRun(trimmed) { return true }
            return !hasCloser(marker: r.marker, length: r.len, after: idx) && r.info.isEmpty
        }

        // ---- the machine ---------------------------------------------------

        var out: [MarkdownChunk] = []
        var buf = ""             // current accumulated chunk
        var blankCount = 0       // deferred blank lines

        var inFence = false
        var fenceChar: Character = "`"
        var fenceLen = 0

        var lastTrimmed = ""     // previous non-blank, trimmed
        var lastRaw     = ""     // previous non-blank, untrimmed (indent test)
        var inList = false       // chunk currently holds an open list

        func emit() {
            let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                out.append(MarkdownChunk(content: t))
            }
            buf = ""
            blankCount = 0
            lastTrimmed = ""
            lastRaw = ""
            inList = false
        }

        for idx in 0..<rawLines.count {
            let raw  = rawLines[idx]
            let trim = raw.trimmingCharacters(in: .whitespaces)

            // ---- code-block mode ------------------------------------------
            if inFence {
                buf += raw + "\n"
                // The line must be a valid closing fence.
                if let r = fenceRun(trim),
                   r.marker == fenceChar,
                   r.len >= fenceLen,
                   r.info.isEmpty {
                    emit()
                    inFence = false
                }
                continue
            }

            // ---- heading -----------------------------------------------
            if trim.hasPrefix("#") {
                emit()
                out.append(MarkdownChunk(content: raw))
                continue
            }

            // ---- fence opening -----------------------------------------
            if let r = fenceRun(trim), !isDivider(trim, at: idx) {
                emit()
                buf = raw + "\n"
                inFence  = true
                fenceChar = r.marker
                fenceLen  = r.len
                continue
            }

            // A decorative run is prose — it must not open a fence.
            // (Implicit: any run that reaches here is a divider or prose.)

            // ---- blank line --------------------------------------------
            if trim.isEmpty {
                if buf.isEmpty { continue }
                if inList, Chunk.isListItem(lastTrimmed) || Chunk.isIndented(lastRaw) {
                    blankCount += 1
                } else {
                    emit()
                }
                continue
            }

            // ---- blank lines held open → keep or flush ----------------
            if blankCount > 0 {
                if Chunk.isListItem(trim) || Chunk.isIndented(raw) {
                    buf += String(repeating: "\n", count: blankCount)
                    blankCount = 0
                } else {
                    emit()
                }
            }

            // ---- list-open state ---------------------------------------
            if Chunk.isListItem(trim) {
                let followsList = Chunk.isListItem(lastTrimmed)
                               || Chunk.isIndented(lastRaw)
                let startsBlock = lastTrimmed.isEmpty
                let followsLeadIn = lastTrimmed.hasSuffix(":") || lastTrimmed.hasSuffix("：")
                if followsList || startsBlock || followsLeadIn || inList {
                    inList = true
                }
            } else if !Chunk.isIndented(raw) {
                inList = false
            }

            buf += raw + "\n"
            lastTrimmed = trim
            lastRaw     = raw
        }

        emit()
        if out.isEmpty {
            out.append(MarkdownChunk(content: text))
        }
        return out
    }
}