import SwiftUI
import AppKit

// Enhanced color preview
struct ColorPreviewView: View {
    let colorString: String
    @State private var color: Color?
    @State private var formats: [ColorFormat] = []
    
    struct ColorFormat {
        let name: String
        let value: String
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let color = color {
                // Large color swatch
                RoundedRectangle(cornerRadius: 12)
                    .fill(color)
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                
                // Color formats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color Formats")
                        .font(.headline)
                    
                    ForEach(Array(formats.enumerated()), id: \.offset) { index, format in
                        HStack {
                            Text(format.name + ":")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)
                            
                            Text(format.value)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            
                            Spacer()
                            
                            Button(action: { copyFormat(format.value) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color(white: 0.95))
                .cornerRadius(8)
                
                // Color info
                if let rgb = extractRGB(from: colorString) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color Information")
                            .font(.headline)
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Red:")
                                    .foregroundColor(.secondary)
                                Text("\(rgb.r)")
                            }
                            
                            GridRow {
                                Text("Green:")
                                    .foregroundColor(.secondary)
                                Text("\(rgb.g)")
                            }
                            
                            GridRow {
                                Text("Blue:")
                                    .foregroundColor(.secondary)
                                Text("\(rgb.b)")
                            }
                            
                            GridRow {
                                Text("Alpha:")
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.2f", rgb.a))
                            }
                        }
                        .font(.caption)
                    }
                    .padding(12)
                    .background(Color(white: 0.95))
                    .cornerRadius(8)
                }
                
                // Quick actions
                HStack {
                    Button(action: { copyFormat(formats.first(where: { $0.name == "HEX" })?.value ?? "") }) {
                        Label("Copy HEX", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { copyFormat(formats.first(where: { $0.name == "RGB" })?.value ?? "") }) {
                        Label("Copy RGB", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { copyAllFormats() }) {
                        Label("Copy All", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
            } else {
                Text("Invalid color format")
                    .foregroundColor(.orange)
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .onAppear {
            parseColor()
        }
    }
    
    private func parseColor() {
        // Try to parse as hex
        var hexSanitized = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        if Scanner(string: hexSanitized).scanHexInt64(&rgb) {
            let length = hexSanitized.count
            var r: Double = 0.0
            var g: Double = 0.0
            var b: Double = 0.0
            var a: Double = 1.0
            
            if length == 6 {
                r = Double((rgb & 0xFF0000) >> 16) / 255.0
                g = Double((rgb & 0x00FF00) >> 8) / 255.0
                b = Double(rgb & 0x0000FF) / 255.0
            } else if length == 8 {
                r = Double((rgb & 0xFF000000) >> 24) / 255.0
                g = Double((rgb & 0x00FF0000) >> 16) / 255.0
                b = Double((rgb & 0x0000FF00) >> 8) / 255.0
                a = Double(rgb & 0x000000FF) / 255.0
            } else {
                color = nil
                return
            }
            
            color = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
            generateFormats(from: colorString)
            return
        }
        
        // Try to parse as RGB
        if let rgbColor = parseRGB(colorString) {
            color = rgbColor
            generateFormats(from: colorString)
            return
        }
        
        color = nil
    }
    
    private func parseRGB(_ string: String) -> Color? {
        // Try formats like "rgb(255, 87, 51)" or "255, 87, 51"
        let patterns = [
            #"rgb\((\d+),\s*(\d+),\s*(\d+)\)"#,
            #"(\d+),\s*(\d+),\s*(\d+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) {
                let rRange = Range(match.range(at: 1), in: string)!
                let gRange = Range(match.range(at: 2), in: string)!
                let bRange = Range(match.range(at: 3), in: string)!
                
                if let r = Int(string[rRange]),
                   let g = Int(string[gRange]),
                   let b = Int(string[bRange]) {
                    return Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
                }
            }
        }
        
        return nil
    }
    
    private func generateFormats(from original: String) {
        guard color != nil else { return }
        
        var formats: [ColorFormat] = []
        
        // HEX
        if let hex = extractHEX(from: original) {
            formats.append(ColorFormat(name: "HEX", value: hex))
        }
        
        // RGB
        if let rgb = extractRGB(from: original) {
            formats.append(ColorFormat(name: "RGB", value: "rgb(\(rgb.r), \(rgb.g), \(rgb.b))"))
            formats.append(ColorFormat(name: "RGBA", value: "rgba(\(rgb.r), \(rgb.g), \(rgb.b), \(String(format: "%.2f", rgb.a)))"))
        }
        
        // HSL (simplified conversion)
        if let rgb = extractRGB(from: original) {
            let hsl = rgbToHSL(rgb)
            formats.append(ColorFormat(name: "HSL", value: "hsl(\(Int(hsl.h)), \(Int(hsl.s * 100))%, \(Int(hsl.l * 100))%)"))
        }
        
        self.formats = formats
    }
    
    private func extractHEX(from string: String) -> String? {
        let cleaned = string.replacingOccurrences(of: "#", with: "").uppercased()
        if cleaned.count == 6 || cleaned.count == 8 {
            return "#" + cleaned
        }
        return nil
    }
    
    private func extractRGB(from string: String) -> (r: Int, g: Int, b: Int, a: Double)? {
        // Try to parse hex color
        var hexSanitized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let length = hexSanitized.count
        var r: Double = 0.0
        var g: Double = 0.0
        var b: Double = 0.0
        var a: Double = 1.0
        
        if length == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        return (Int(r * 255), Int(g * 255), Int(b * 255), a)
    }
    
    private func extractRGB(from color: Color) -> (r: Int, g: Int, b: Int, a: Double)? {
        let nsColor = NSColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255), Int(g * 255), Int(b * 255), Double(a))
    }
    
    private func rgbToHSL(_ rgb: (r: Int, g: Int, b: Int, a: Double)) -> (h: Double, s: Double, l: Double) {
        let r = Double(rgb.r) / 255.0
        let g = Double(rgb.g) / 255.0
        let b = Double(rgb.b) / 255.0
        
        let max = Swift.max(r, g, b)
        let min = Swift.min(r, g, b)
        let delta = max - min
        
        var h: Double = 0
        var s: Double = 0
        let l = (max + min) / 2.0
        
        if delta != 0 {
            s = l > 0.5 ? delta / (2.0 - max - min) : delta / (max + min)
            
            if max == r {
                h = ((g - b) / delta) + (g < b ? 6 : 0)
            } else if max == g {
                h = ((b - r) / delta) + 2
            } else {
                h = ((r - g) / delta) + 4
            }
            h /= 6.0
        }
        
        return (h * 360, s, l)
    }
    
    private func copyFormat(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
    
    private func copyAllFormats() {
        let allFormats = formats.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        copyFormat(allFormats)
    }
}

