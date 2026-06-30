import SwiftUI
import AppKit

// URL preview with link preview
struct URLPreviewView: View {
    @Environment(\.colorScheme) private var scheme
    let urlString: String
    @State private var urlInfo: URLInfo?
    @State private var isLoading = false

    struct URLInfo {
        let url: URL
        let title: String?
        let description: String?
        let isValid: Bool
    }

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            // URL display
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(c.accent)

                Text(urlString)
                    .font(.dsMonoBody)
                    .foregroundColor(c.text)
                    .textSelection(.enabled)
                    .lineLimit(2)

                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(c.card))

            // URL info
            if let info = urlInfo {
                if info.isValid {
                    if (info.title?.isEmpty == false) || (info.description?.isEmpty == false) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let title = info.title, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(c.text)
                            }

                            if let description = info.description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 11))
                                    .foregroundColor(c.text2)
                                    .lineLimit(3)
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(c.card))
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Invalid URL")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                }
            } else if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading URL info...")
                        .font(.system(size: 11))
                        .foregroundColor(c.text2)
                }
                .padding(12)
            }

            // Actions
            if let url = urlInfo?.url, urlInfo?.isValid == true {
                HStack(spacing: 8) {
                    Button(action: { openURL(url) }) {
                        Label("打开链接", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .dsButton(.prominent)

                    Button(action: { copyURL() }) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .dsButton(.secondary)
                }
            }
        }
        .onAppear {
            validateURL()
        }
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }
    
    private func validateURL() {
        guard let url = URL(string: urlString) else {
            urlInfo = URLInfo(url: URL(string: "about:blank")!, title: nil, description: nil, isValid: false)
            return
        }
        
        urlInfo = URLInfo(url: url, title: nil, description: nil, isValid: true)
        
        // Try to fetch URL metadata (simplified - in production would use proper HTML parsing)
        isLoading = true
        Task {
            // Basic validation - in a real app, you'd fetch and parse HTML
            // For now, just validate the URL structure
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

