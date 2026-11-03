import Foundation

/// Re-indents JSON text without re-serializing it. Round-tripping through
/// JSONSerialization rewrote the user's data — 19.99 became 19.989999999999998
/// and every "/" became "\/" — and Copy put that on the clipboard. Working on
/// the source bytes keeps number literals, escapes and key order verbatim.
/// Input must already be valid JSON (callers validate with JSONSerialization).
enum JSONTextFormatting {
    static func pretty(_ json: String) -> String { format(json, pretty: true) }
    static func minified(_ json: String) -> String { format(json, pretty: false) }

    private static func format(_ json: String, pretty: Bool) -> String {
        // JSONSerialization accepts a leading BOM; it must not reach the copied text
        var bytes = Array(json.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var out: [UInt8] = []
        out.reserveCapacity(pretty ? bytes.count * 2 : bytes.count)
        var depth = 0
        var inString = false
        var escaped = false

        func isWhitespace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }
        func newline() {
            out.append(0x0A)
            out.append(contentsOf: repeatElement(0x20, count: depth * 2))
        }

        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if inString {
                // Multi-byte UTF-8 never contains ASCII bytes, so copying
                // byte-by-byte keeps every character inside strings intact
                out.append(b)
                if escaped { escaped = false } else if b == 0x5C { escaped = true } else if b == 0x22 { inString = false }
                i += 1
                continue
            }
            switch b {
            case 0x22: // "
                inString = true
                out.append(b)
            case 0x7B, 0x5B: // { [
                out.append(b)
                // An empty container stays on one line: {} / []
                var j = i + 1
                while j < bytes.count, isWhitespace(bytes[j]) { j += 1 }
                if j < bytes.count, bytes[j] == (b == 0x7B ? 0x7D : 0x5D) {
                    out.append(bytes[j])
                    i = j + 1
                    continue
                }
                depth += 1
                if pretty { newline() }
            case 0x7D, 0x5D: // } ]
                depth -= 1
                if pretty { newline() }
                out.append(b)
            case 0x2C: // ,
                out.append(b)
                if pretty { newline() }
            case 0x3A: // :
                out.append(contentsOf: pretty ? [0x20, 0x3A, 0x20] : [0x3A])
            default:
                if !isWhitespace(b) { out.append(b) }
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }
}
