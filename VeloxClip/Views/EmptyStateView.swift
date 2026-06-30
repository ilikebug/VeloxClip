import SwiftUI

/// Centered empty/placeholder state used by the clipboard list (history empty,
/// no search match, favorites empty). Pixel-faithful to the design kit.
struct EmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(c.text3)
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(c.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(c.text2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
