import Foundation

/// Pure (string → string) color formatting shared by the command palette and the
/// color preview, so they can never disagree. Handles every color form that
/// `ClipboardMonitor.isColor` accepts: 3/6/8-digit hex and `rgb()/rgba()`.
enum ColorFormatting {
    /// Parsed 8-bit RGB(A) components from any accepted color form, or nil.
    static func components(from content: String) -> (r: Int, g: Int, b: Int, a: Double)? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rgb = parseRGBFunction(trimmed) { return rgb }
        return parseHex(trimmed)
    }

    /// Normalized uppercase `#RRGGBB` for any accepted form, or nil if unparseable.
    static func hex(from content: String) -> String? {
        guard let c = components(from: content) else { return nil }
        return String(format: "#%02X%02X%02X", c.r, c.g, c.b)
    }

    /// Space-separated `"R G B"` for any accepted form, or nil if unparseable.
    static func rgb(from content: String) -> String? {
        guard let c = components(from: content) else { return nil }
        return "\(c.r) \(c.g) \(c.b)"
    }

    // MARK: Parsing

    private static func parseHex(_ string: String) -> (r: Int, g: Int, b: Int, a: Double)? {
        let cleaned = string.replacingOccurrences(of: "#", with: "")
        let length = cleaned.count
        guard length == 3 || length == 6 || length == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        switch length {
        case 3:
            // #RGB → each nibble doubled (e.g. f00 → FF0000)
            let r = (value & 0xF00) >> 8
            let g = (value & 0x0F0) >> 4
            let b = value & 0x00F
            return (Int(r * 17), Int(g * 17), Int(b * 17), 1.0)
        case 6:
            return (Int((value & 0xFF0000) >> 16),
                    Int((value & 0x00FF00) >> 8),
                    Int(value & 0x0000FF),
                    1.0)
        default: // 8
            return (Int((value & 0xFF000000) >> 24),
                    Int((value & 0x00FF0000) >> 16),
                    Int((value & 0x0000FF00) >> 8),
                    Double(value & 0x000000FF) / 255.0)
        }
    }

    private static func parseRGBFunction(_ string: String) -> (r: Int, g: Int, b: Int, a: Double)? {
        let pattern = #"rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let rRange = Range(match.range(at: 1), in: string),
              let gRange = Range(match.range(at: 2), in: string),
              let bRange = Range(match.range(at: 3), in: string),
              let r = Int(string[rRange]),
              let g = Int(string[gRange]),
              let b = Int(string[bRange])
        else { return nil }

        var alpha = 1.0
        if match.numberOfRanges > 4, match.range(at: 4).location != NSNotFound,
           let aRange = Range(match.range(at: 4), in: string) {
            alpha = Double(string[aRange]) ?? 1.0
        }
        return (r, g, b, alpha)
    }
}
