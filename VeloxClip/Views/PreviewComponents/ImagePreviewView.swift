import SwiftUI
import AppKit

// Enhanced image preview with info and controls
struct ImagePreviewView: View {
    @Environment(\.colorScheme) private var scheme
    let imageData: Data
    @ObservedObject private var settings = AppSettings.shared
    // The image is always fitted to the panel width, so 1.0 is both the default and the ceiling
    private static let maximumZoom: CGFloat = 1.0
    @State private var zoomLevel: CGFloat = ImagePreviewView.maximumZoom
    @State private var imageContainerWidth: CGFloat = 0
    @State private var imageInfo: ImageInfo?
    @State private var displayImage: NSImage?
    
    struct ImageInfo {
        let size: NSSize
        let fileSize: Int
        let format: String
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
                Text(L10n.string("preview.image.loadFailed", language: settings.appLanguage)).font(.system(size: 12)).foregroundColor(c.text2)
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
            Text(L10n.string("preview.image.loading", language: settings.appLanguage)).font(.system(size: 11)).foregroundColor(c.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    @ViewBuilder
    private func imageDisplay(_ nsImage: NSImage) -> some View {
        let c = DSColors(scheme: scheme)
        let sidePadding: CGFloat = 32
        let availableWidth = max(1, imageContainerWidth - sidePadding)
        let displaySize = imageContainerWidth > 0
            ? fittedImageSize(imageSize: nsImage.size, availableWidth: availableWidth, zoomLevel: zoomLevel)
            : nil

        Group {
            if let displaySize {
                imageView(nsImage)
                    .frame(width: displaySize.width, height: displaySize.height)
            } else {
                imageView(nsImage)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(16)
        .background(c.card)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ImagePreviewWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ImagePreviewWidthPreferenceKey.self) { width in
            imageContainerWidth = width
        }
    }

    private func imageView(_ nsImage: NSImage) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(nsImage.size, contentMode: .fit)
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

            Button(action: { zoomLevel = min(Self.maximumZoom, zoomLevel + 0.25) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .dsButton(small: true)
            .disabled(zoomLevel >= Self.maximumZoom)

            Button(L10n.string("preview.image.fit", language: settings.appLanguage)) { zoomLevel = Self.maximumZoom }.dsButton(small: true)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var infoSection: some View {
        let c = DSColors(scheme: scheme)
        if let info = imageInfo {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("preview.image.info", language: settings.appLanguage)).font(.system(size: 13, weight: .semibold)).foregroundColor(c.text)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    imageInfoRow(label: L10n.string("preview.image.dimensions", language: settings.appLanguage), value: "\(Int(info.size.width)) × \(Int(info.size.height)) px")
                    imageInfoRow(label: L10n.string("preview.image.fileSize", language: settings.appLanguage), value: formatFileSize(info.fileSize))
                    imageInfoRow(label: L10n.string("preview.image.format", language: settings.appLanguage), value: info.format)
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
            
            if let bitmapRep = imageRep as? NSBitmapImageRep {
                format = bitmapRep.bitmapFormat.contains(.alphaFirst) ? "PNG" : "JPEG"
            }
            
            if format == "Unknown" {
                if imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) { format = "PNG" }
                else if imageData.starts(with: [0xFF, 0xD8, 0xFF]) { format = "JPEG" }
                else if imageData.starts(with: [0x52, 0x49, 0x46, 0x46]) { format = "WebP" }
            }
            
            let info = ImageInfo(size: size, fileSize: fileSize, format: format)
            return (nsImage, info)
        }.value
        
        await MainActor.run {
            self.displayImage = result.0
            self.imageInfo = result.1
            self.isLoading = false
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        FilePreviewPresentation.fileSizeString(Int64(bytes))
    }

    private func fittedImageSize(imageSize: NSSize, availableWidth: CGFloat, zoomLevel: CGFloat) -> CGSize {
        let width = min(availableWidth, imageSize.width * zoomLevel)
        let aspect = imageSize.height / max(imageSize.width, 1)
        return CGSize(width: width, height: width * aspect)
    }
}

private struct ImagePreviewWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
