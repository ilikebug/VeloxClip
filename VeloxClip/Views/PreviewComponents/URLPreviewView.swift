import SwiftUI
import AppKit

// URL preview with link preview
struct URLPreviewView: View {
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
        VStack(alignment: .leading, spacing: 12) {
            // URL display
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.blue)
                
                Text(urlString)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                
                Spacer()
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            
            // URL info
            if let info = urlInfo {
                if info.isValid {
                    VStack(alignment: .leading, spacing: 12) {
                        if let title = info.title, !title.isEmpty {
                            Text(title)
                                .font(.headline)
                        }
                        
                        if let description = info.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Invalid URL")
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            } else if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading URL info...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
            }
            
            // Actions
            HStack {
                if let url = urlInfo?.url, urlInfo?.isValid == true {
                    Button(action: { openURL(url) }) {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
            }
        }
        .onAppear {
            validateURL()
        }
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

