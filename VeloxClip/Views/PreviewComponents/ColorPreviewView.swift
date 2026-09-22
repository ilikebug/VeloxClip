import SwiftUI
import AppKit

// Enhanced color preview
struct ColorPreviewView: View {
    @Environment(\.colorScheme) private var scheme
    let colorString: String
    @ObservedObject private var settings = AppSettings.shared
    @State private var color: Color?
    @State private var formats: [ColorFormat] = []

    struct ColorFormat {
        let name: String
        let value: String
    }

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            if let color = color {
                // Large color swatch (the swatch fill is content — keep as-is)
                RoundedRectangle(cornerRadius: 12)
                    .fill(color)
                    .frame(height: 128)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(c.divider, lineWidth: 1)
                    )

                // Color value rows
                VStack(spacing: 8) {
                    ForEach(Array(formats.enumerated()), id: \.offset) { _, format in
                        HStack {
                            Text(format.name)
                                .font(.system(size: 11))
                                .foregroundColor(c.text2)

                            Spacer(minLength: 12)

                            Text(format.value)
                                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(c.text)
                                .textSelection(.enabled)

                            Button(action: { copyFormat(format.value) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(c.text2)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(c.field))
                    }
                }

                // Color info
                if let rgb = ColorFormatting.components(from: colorString) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.string("preview.color.info", language: settings.appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(c.text)

                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                            GridRow {
                                infoLabel(L10n.string("preview.color.red", language: settings.appLanguage))
                                Text("\(rgb.r)").font(.dsMonoBody).foregroundColor(c.text)
                                infoLabel(L10n.string("preview.color.green", language: settings.appLanguage))
                                Text("\(rgb.g)").font(.dsMonoBody).foregroundColor(c.text)
                            }

                            GridRow {
                                infoLabel(L10n.string("preview.color.blue", language: settings.appLanguage))
                                Text("\(rgb.b)").font(.dsMonoBody).foregroundColor(c.text)
                                infoLabel(L10n.string("preview.color.alpha", language: settings.appLanguage))
                                Text(String(format: "%.2f", rgb.a)).font(.dsMonoBody).foregroundColor(c.text)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(c.card))
                }

                // Quick actions
                HStack {
                    Button(action: {
                        // Route through the shared formatter so the palette and the
                        // preview can never disagree on the canonical #RRGGBB.
                        // Falls back to the displayed HEX value if unparseable.
                        let displayed = formats.first(where: { $0.name == "HEX" })?.value ?? ""
                        copyFormat(ColorFormatting.hex(from: colorString) ?? displayed)
                    }) {
                        Label(L10n.string("command.copyHex", language: settings.appLanguage), systemImage: "doc.on.doc")
                    }
                    .dsButton()

                    Button(action: { copyFormat(formats.first(where: { $0.name == "RGB" })?.value ?? "") }) {
                        Label(L10n.string("command.copyRgb", language: settings.appLanguage), systemImage: "doc.on.doc")
                    }
                    .dsButton()

                    Button(action: { copyAllFormats() }) {
                        Label(L10n.string("preview.color.copyAll", language: settings.appLanguage), systemImage: "doc.on.doc.fill")
                    }
                    .dsButton(.prominent)

                    Spacer()
                }
            } else {
                Text(L10n.string("preview.color.invalid", language: settings.appLanguage))
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
        }
        .onAppear {
            parseColor()
        }
    }

    private func infoLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(DSColors(scheme: scheme).text2)
    }
    
    private func parseColor() {
        // All color parsing flows through the shared ColorFormatting helper so the
        // preview can never disagree with the ⌘K palette / list-row swatch. It
        // accepts every form ClipboardMonitor.isColor stores (3/6/8-digit hex and
        // rgb()/rgba()), so 3-digit hex like "#f00" now renders instead of showing
        // "无效的颜色格式".
        if let comp = ColorFormatting.components(from: colorString) {
            let parsed = Color(.sRGB,
                               red: Double(comp.r) / 255.0,
                               green: Double(comp.g) / 255.0,
                               blue: Double(comp.b) / 255.0,
                               opacity: comp.a)
            color = parsed
            // Pass the EXACT parsed channels. Re-deriving them from the Color
            // went through NSColor's extended-sRGB components, where an exact
            // 11 comes back as 10.999997 and Int() floors it — 75 of 256 values
            // displayed one lower than the colour the user actually copied.
            generateFormats(from: comp)
            return
        }
        color = nil
    }

    private func generateFormats(from rgb: (r: Int, g: Int, b: Int, a: Double)) {
        // Row construction lives in ColorPreviewFormats so it can be asserted
        // directly; it works from the exact parsed components.
        formats = ColorPreviewFormats.rows(for: rgb).map {
            ColorFormat(name: $0.name, value: $0.value)
        }
    }

    private func copyFormat(_ value: String) {
        PasteboardService.shared.write(text: value)
    }
    
    private func copyAllFormats() {
        let allFormats = formats.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        copyFormat(allFormats)
    }
}
