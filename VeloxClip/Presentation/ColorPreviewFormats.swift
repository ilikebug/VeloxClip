import Foundation

/// The rows shown in the colour detail panel, as data.
///
/// Extracted from `ColorPreviewView` so the values can be asserted directly.
/// The panel used to re-derive its channel values from the parsed SwiftUI
/// `Color` via `NSColor.getRed` and truncate with `Int(r * 255)`; NSColor
/// returns extended-sRGB components, where an exact 11 comes back as
/// 10.999997, so 75 of 256 values displayed one lower than the colour the user
/// copied — while the Copy-HEX button formatted the original string, so the row
/// and the button disagreed. Everything here is computed from the exact
/// components `ColorFormatting` parsed.
enum ColorPreviewFormats {
    struct Row: Equatable {
        let name: String
        let value: String
    }

    static func rows(for rgb: (r: Int, g: Int, b: Int, a: Double)) -> [Row] {
        var rows: [Row] = []
        let source = "rgb(\(rgb.r), \(rgb.g), \(rgb.b))"

        let hex = ColorFormatting.hex(from: source)
            ?? String(format: "#%02X%02X%02X", rgb.r, rgb.g, rgb.b)
        rows.append(Row(name: "HEX", value: hex))

        if rgb.a < 1.0 {
            rows.append(Row(name: "HEXA",
                            value: String(format: "#%02X%02X%02X%02X",
                                          rgb.r, rgb.g, rgb.b, Int((rgb.a * 255).rounded()))))
        }

        let rgbValue = ColorFormatting.rgb(from: source) ?? "\(rgb.r) \(rgb.g) \(rgb.b)"
        rows.append(Row(name: "RGB", value: rgbValue))

        if rgb.a < 1.0 {
            rows.append(Row(name: "RGBA",
                            value: "\(rgb.r) \(rgb.g) \(rgb.b) \(String(format: "%.2f", rgb.a))"))
        }

        let hsl = toHSL(rgb)
        rows.append(Row(name: "HSL",
                        value: "\(Int(hsl.h)) \(Int(hsl.s * 100)) \(Int(hsl.l * 100))"))

        return rows
    }

    static func toHSL(_ rgb: (r: Int, g: Int, b: Int, a: Double)) -> (h: Double, s: Double, l: Double) {
        let r = Double(rgb.r) / 255.0
        let g = Double(rgb.g) / 255.0
        let b = Double(rgb.b) / 255.0

        let maxValue = Swift.max(r, g, b)
        let minValue = Swift.min(r, g, b)
        let delta = maxValue - minValue

        var h: Double = 0
        var s: Double = 0
        let l = (maxValue + minValue) / 2.0

        if delta != 0 {
            s = l > 0.5 ? delta / (2.0 - maxValue - minValue) : delta / (maxValue + minValue)

            if maxValue == r {
                h = ((g - b) / delta) + (g < b ? 6 : 0)
            } else if maxValue == g {
                h = ((b - r) / delta) + 2
            } else {
                h = ((r - g) / delta) + 4
            }
            h /= 6.0
        }

        return (h * 360, s, l)
    }
}
