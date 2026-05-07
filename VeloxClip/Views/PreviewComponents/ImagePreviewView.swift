import SwiftUI
import AppKit

// Enhanced image preview with info and controls
struct ImagePreviewView: View {
    let imageData: Data
    @State private var zoomLevel: CGFloat = 1.0
    @State private var imageInfo: ImageInfo?
    @State private var displayImage: NSImage?
    
    struct ImageInfo: Sendable {
        let size: NSSize
        let fileSize: Int
        let format: String
        let colorSpace: String?
        let hasAlpha: Bool
    }
    
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                loadingPlaceholder
            } else if let nsImage = displayImage {
                imageDisplay(nsImage)
                zoomControls
                infoSection
            } else {
                Text("Unable to load image").foregroundColor(.secondary)
            }
        }
        .task(id: imageData) {
            await loadImageAsync()
        }
    }
    
    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading image...").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    
    @ViewBuilder
    private func imageDisplay(_ nsImage: NSImage) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .scaledToFit()
            .scaleEffect(zoomLevel)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            .background(Color.secondary.opacity(0.05))
    }
    
    private var zoomControls: some View {
        HStack {
            Button(action: { zoomLevel = max(0.25, zoomLevel - 0.25) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered).controlSize(.small)
            
            Text("\(Int(zoomLevel * 100))%")
                .font(.caption).foregroundColor(.secondary).frame(width: 60)
            
            Button(action: { zoomLevel = min(3.0, zoomLevel + 0.25) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered).controlSize(.small)
            
            Button("Fit") { zoomLevel = 1.0 }.buttonStyle(.bordered).controlSize(.small)
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var infoSection: some View {
        if let info = imageInfo {
            VStack(alignment: .leading, spacing: 12) {
                Text("Information").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    imageInfoRow(label: "Dimensions", value: "\(Int(info.size.width)) × \(Int(info.size.height)) px")
                    imageInfoRow(label: "File Size", value: formatFileSize(info.fileSize))
                    imageInfoRow(label: "Format", value: info.format)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }
    
    private func imageInfoRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
        }
    }
    
    private func loadImageAsync() async {
        isLoading = true

        // Decode metadata off-main; do not pass NSImage across actor boundaries
        // (NSImage is not Sendable on Swift <= 6.1). We reconstruct it on the
        // main actor below — NSImage(data:) is cheap; the heavy work was the
        // bitmap-rep inspection that ran inside the detached task.
        let data = imageData
        let info = await Task.detached(priority: .userInitiated) { () -> ImageInfo? in
            guard let nsImage = NSImage(data: data),
                  let imageRep = nsImage.representations.first else {
                return nil
            }

            let size = imageRep.size
            let fileSize = data.count
            var format = "Unknown"
            var colorSpace: String? = nil
            var hasAlpha = false

            if let bitmapRep = imageRep as? NSBitmapImageRep {
                format = bitmapRep.bitmapFormat.contains(.alphaFirst) ? "PNG" : "JPEG"
                colorSpace = bitmapRep.colorSpace.localizedName
                hasAlpha = bitmapRep.hasAlpha
            }

            if format == "Unknown" {
                if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { format = "PNG" }
                else if data.starts(with: [0xFF, 0xD8, 0xFF]) { format = "JPEG" }
                else if data.starts(with: [0x52, 0x49, 0x46, 0x46]) { format = "WebP" }
            }

            return ImageInfo(size: size, fileSize: fileSize, format: format, colorSpace: colorSpace, hasAlpha: hasAlpha)
        }.value

        self.displayImage = NSImage(data: imageData)
        self.imageInfo = info
        self.isLoading = false
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}


