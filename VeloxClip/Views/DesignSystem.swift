import SwiftUI

struct DesignSystem {
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "#6366f1")!, Color(hex: "#a855f7")!],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
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
