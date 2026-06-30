import SwiftUI
import AppKit

struct DesignSystem {
    /// 面板投影：0 18px 50px rgba(0,0,0,.2)（深色 .5）
    static func panelShadow(_ scheme: ColorScheme) -> Color {
        .black.opacity(scheme == .dark ? 0.5 : 0.2)
    }

    static let backgroundBlur = VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)

    struct Card: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding()
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
    }
}

extension View {
    func premiumCard() -> some View {
        self.modifier(DesignSystem.Card())
    }
}

// MARK: - Compact dropdown style
//
// System-native menu/picker chrome (`.menuStyle(.button)`, `.pickerStyle(.menu)`)
// is drawn by the macOS version the app *runs on*, so the same build looks
// different across macOS releases. We render our own label so the dropdown looks
// identical everywhere; pair it with `.menuStyle(.borderlessButton)` +
// `.menuIndicator(.hidden)` on the Menu so the system adds no chrome of its own.
struct CompactMenuLabel: ViewModifier {
    var width: CGFloat? = nil

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

extension View {
    /// Custom, version-stable chrome for a `Menu` label. Pass `width` for
    /// fixed-width dropdowns (selection text left-aligned), omit it to size to content.
    func compactMenuLabel(width: CGFloat? = nil) -> some View {
        modifier(CompactMenuLabel(width: width))
    }
}

// MARK: - Shared Components

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Fixed typography
//
// Semantic fonts (.body, .caption, .headline…) scale with the user's
// "System Settings → Accessibility → Text Size" / Dynamic Type setting, so the
// same screen wraps and sizes differently across machines. These fixed-point
// tokens render identically everywhere. Sizes mirror macOS defaults at standard
// text size, so the app looks the same as before — just no longer scalable.
extension Font {
    static let dsCaption2    = Font.system(size: 10)
    static let dsCaption     = Font.system(size: 11)
    static let dsFootnote    = Font.system(size: 11)
    static let dsSubheadline = Font.system(size: 12)
    static let dsCallout     = Font.system(size: 12)
    static let dsBody        = Font.system(size: 13)
    static let dsHeadline    = Font.system(size: 13, weight: .semibold)
    static let dsTitle3      = Font.system(size: 15)
    static let dsTitle2      = Font.system(size: 17)
    static let dsTitle       = Font.system(size: 22)
    static let dsLargeTitle  = Font.system(size: 26)
    /// Monospaced body, for code / hex / numeric values.
    static let dsMonoBody    = Font.system(size: 13, design: .monospaced)
}

// MARK: - Buttons
//
// `.bordered` / `.borderedProminent` are drawn by the running macOS version, so
// their corners/padding/shadow differ across releases. This self-drawn style is
// version-stable. `.prominent` = primary action (gradient), `.secondary` = the
// default subtle filled button. Pass `small: true` for compact toolbars.
struct DSButtonStyle: ButtonStyle {
    enum Kind { case secondary, prominent, destructive }
    var kind: Kind = .secondary
    var small: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 11 : 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, small ? 8 : 12)
            .padding(.vertical, small ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .overlay {
                if kind != .prominent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .prominent: return AnyShapeStyle(.white)
        case .secondary: return AnyShapeStyle(Color.primary)
        case .destructive: return AnyShapeStyle(Color.red)
        }
    }

    private var borderColor: Color {
        kind == .destructive ? Color.red.opacity(0.35) : Color.primary.opacity(0.12)
    }

    private func fill(pressed: Bool) -> AnyShapeStyle {
        switch kind {
        case .prominent: return AnyShapeStyle(Color(nsColor: .controlAccentColor))
        case .secondary: return AnyShapeStyle(Color.primary.opacity(pressed ? 0.16 : 0.08))
        case .destructive: return AnyShapeStyle(Color.red.opacity(pressed ? 0.22 : 0.1))
        }
    }
}

extension View {
    func dsButton(_ kind: DSButtonStyle.Kind = .secondary, small: Bool = false) -> some View {
        buttonStyle(DSButtonStyle(kind: kind, small: small))
    }
}

// MARK: - Text field
//
// `.roundedBorder` chrome (border thickness, focus ring) was redrawn in macOS 13/14.
// Pair `.textFieldStyle(.plain)` with this for a version-stable field.
extension View {
    func dsTextField(width: CGFloat? = nil) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Toggle (self-drawn switch)
struct DSSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(Color(nsColor: .controlAccentColor)) : AnyShapeStyle(Color.primary.opacity(0.22)))
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
        }
        // Whole row toggles (label included), matching native .switch behavior
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { configuration.isOn.toggle() }
        }
    }
}

extension ToggleStyle where Self == DSSwitchToggleStyle {
    static var dsSwitch: DSSwitchToggleStyle { DSSwitchToggleStyle() }
}

// MARK: - Slider (self-drawn)
//
// Native `Slider` thumb/track were redesigned in macOS 13. This draws its own.
struct DSSlider<V: BinaryFloatingPoint>: View {
    @Binding var value: V
    let range: ClosedRange<V>

    init(value: Binding<V>, in range: ClosedRange<V>) {
        self._value = value
        self.range = range
    }

    private let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // The thumb center travels [thumb/2, w - thumb/2], so map value over the
            // usable track (w - thumb) and keep fill + thumb + cursor in lock-step.
            let usable = max(w - thumb, 1)
            let span = range.upperBound - range.lowerBound
            let raw = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
            let frac = min(max(raw, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: 4)
                Capsule().fill(Color(nsColor: .controlAccentColor))
                    .frame(width: thumb / 2 + frac * usable, height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .offset(x: frac * usable)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(max((g.location.x - thumb / 2) / usable, 0), 1)
                    value = range.lowerBound + V(f) * span
                }
            )
        }
        .frame(height: 16)
    }
}

// MARK: - Glass background (respects "Reduce Transparency")
//
// SwiftUI materials adapt to the accessibility setting automatically, but pinning
// an explicit opaque fallback keeps the look predictable everywhere.
struct GlassBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if reduceTransparency {
                // Adapts to the active light/dark appearance
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}

extension View {
    func dsGlassBackground(cornerRadius: CGFloat) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Keyboard badge (⌘1 / ⏎ / space)
struct DSKeyBadge: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    var body: some View {
        let c = DSColors(scheme: scheme)
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(c.text2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(c.key))
    }
}

// MARK: - Design tokens (light = 设计图; dark = 推导)
//
// 设计图《VeloxClip 界面套件》全程无渐变，统一系统蓝 #0A84FF。
// 取值随当前 colorScheme 切换；强调色跟随系统（回退 #0A84FF）。
extension Color {
    static func ds(_ light: String, _ dark: String, _ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? dark : light) ?? .clear
    }
}

struct DSColors {
    let scheme: ColorScheme
    // 强调色跟随系统：用 AppKit controlAccentColor，回退 #0A84FF
    var accent: Color { Color(nsColor: .controlAccentColor) }
    // accentSoft 固定蓝色淡底（不跟随系统强调色），对应设计图 --accent-soft
    var accentSoft: Color { Color(.sRGB, red: 10/255, green: 132/255, blue: 1, opacity: scheme == .dark ? 0.22 : 0.14) }
    var text: Color   { .ds("#1d1d1f", "#f5f5f7", scheme) }
    var text2: Color  { .ds("#86868b", "#98989d", scheme) }
    var text3: Color  { .ds("#aeaeb2", "#636366", scheme) }
    var window: Color { .ds("#f4f3f1", "#1e1e1e", scheme) }
    var card: Color   { .ds("#ffffff", "#2c2c2e", scheme) }
    var panel: Color  { scheme == .dark ? Color(.sRGB, red: 40/255, green: 40/255, blue: 42/255, opacity: 0.80)
                                        : Color(.sRGB, red: 250/255, green: 250/255, blue: 249/255, opacity: 0.78) }
    func blackAlpha(_ a: Double, _ darkWhiteA: Double) -> Color {
        scheme == .dark ? Color.white.opacity(darkWhiteA) : Color.black.opacity(a)
    }
    var field: Color   { blackAlpha(0.055, 0.08) }
    var chip: Color    { blackAlpha(0.05, 0.07) }
    var key: Color     { blackAlpha(0.06, 0.10) }
    var divider: Color { blackAlpha(0.09, 0.12) }
    var hover: Color   { blackAlpha(0.045, 0.06) }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        var r: Double = 0.0
        var g: Double = 0.0
        var b: Double = 0.0
        var a: Double = 1.0
        
        let length = hexSanitized.count
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
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
        
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
