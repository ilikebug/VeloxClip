import SwiftUI
import MarkdownUI

struct MarkdownView: View {
    let markdown: String
    
    var body: some View {
        ScrollView {
            Markdown(markdown)
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
                        .font(.largeTitle.bold())
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                .markdownBlockStyle(\.heading2) { configuration in
                    configuration.label
                        .font(.title.bold())
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                .markdownBlockStyle(\.heading3) { configuration in
                    configuration.label
                        .font(.title2.bold())
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                .markdownBlockStyle(\.heading4) { configuration in
                    configuration.label
                        .font(.title3.bold())
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                .markdownBlockStyle(\.heading5) { configuration in
                    configuration.label
                        .font(.headline.bold())
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                .markdownBlockStyle(\.heading6) { configuration in
                    configuration.label
                        .font(.subheadline.bold())
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
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

