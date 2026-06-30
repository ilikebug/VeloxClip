import SwiftUI
import AppKit

// Enhanced image preview with info and controls
struct ImagePreviewView: View {
    @Environment(\.colorScheme) private var scheme
    let imageData: Data
    @State private var zoomLevel: CGFloat = 1.0
    @State private var imageInfo: ImageInfo?
    @State private var displayImage: NSImage?
    
    struct ImageInfo {
        let size: NSSize
        let fileSize: Int
        let format: String
        let colorSpace: String?
        let hasAlpha: Bool
    }
    
    @State private var isLoading = true
    
    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                loadingPlaceholder
            } else if let nsImage = displayImage {
                imageDisplay(nsImage)
                zoomControls
                infoSection
            } else {
                Text("无法加载图片").font(.system(size: 12)).foregroundColor(c.text2)
            }
        }
        .task(id: imageData) {
            await loadImageAsync()
        }
    }
    
    private var loadingPlaceholder: some View {
        let c = DSColors(scheme: scheme)
        return VStack(spacing: 12) {
            ProgressView()
            Text("加载图片中…").font(.system(size: 11)).foregroundColor(c.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    @ViewBuilder
    private func imageDisplay(_ nsImage: NSImage) -> some View {
        let c = DSColors(scheme: scheme)
        Image(nsImage: nsImage)
            .resizable()
            .scaledToFit()
            .scaleEffect(zoomLevel)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            .background(c.card)
    }

    private var zoomControls: some View {
        let c = DSColors(scheme: scheme)
        return HStack {
            Button(action: { zoomLevel = max(0.25, zoomLevel - 0.25) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .dsButton(small: true)

            Text("\(Int(zoomLevel * 100))%")
                .font(.system(size: 11)).foregroundColor(c.text2).frame(width: 60)

            Button(action: { zoomLevel = min(3.0, zoomLevel + 0.25) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .dsButton(small: true)

            Button("适应") { zoomLevel = 1.0 }.dsButton(small: true)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var infoSection: some View {
        let c = DSColors(scheme: scheme)
        if let info = imageInfo {
            VStack(alignment: .leading, spacing: 12) {
                Text("信息").font(.system(size: 13, weight: .semibold)).foregroundColor(c.text)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    imageInfoRow(label: "尺寸", value: "\(Int(info.size.width)) × \(Int(info.size.height)) px")
                    imageInfoRow(label: "文件大小", value: formatFileSize(info.fileSize))
                    imageInfoRow(label: "格式", value: info.format)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(c.card))
            .padding(.horizontal, 16)
        }
    }

    private func imageInfoRow(label: String, value: String) -> some View {
        let c = DSColors(scheme: scheme)
        return GridRow {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(c.text2)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(c.text)
        }
    }
    
    private func loadImageAsync() async {
        isLoading = true
        
        let result = await Task.detached(priority: .userInitiated) { @Sendable in
            guard let nsImage = NSImage(data: imageData),
                  let imageRep = nsImage.representations.first else {
                return (nil, nil) as (NSImage?, ImageInfo?)
            }
            
            let size = imageRep.size
            let fileSize = imageData.count
            var format = "Unknown"
            var colorSpace: String? = nil
            var hasAlpha = false
            
            if let bitmapRep = imageRep as? NSBitmapImageRep {
                format = bitmapRep.bitmapFormat.contains(.alphaFirst) ? "PNG" : "JPEG"
                colorSpace = bitmapRep.colorSpace.localizedName
                hasAlpha = bitmapRep.hasAlpha
            }
            
            if format == "Unknown" {
                if imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) { format = "PNG" }
                else if imageData.starts(with: [0xFF, 0xD8, 0xFF]) { format = "JPEG" }
                else if imageData.starts(with: [0x52, 0x49, 0x46, 0x46]) { format = "WebP" }
            }
            
            let info = ImageInfo(size: size, fileSize: fileSize, format: format, colorSpace: colorSpace, hasAlpha: hasAlpha)
            return (nsImage, info)
        }.value
        
        await MainActor.run {
            self.displayImage = result.0
            self.imageInfo = result.1
            self.isLoading = false
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}


