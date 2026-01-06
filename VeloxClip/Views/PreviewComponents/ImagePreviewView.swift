import SwiftUI
import AppKit

// Enhanced image preview with info and controls
struct ImagePreviewView: View {
    let imageData: Data
    @State private var zoomLevel: CGFloat = 1.0
    @State private var imageInfo: ImageInfo?
    
    struct ImageInfo {
        let size: NSSize
        let fileSize: Int
        let format: String
        let colorSpace: String?
        let hasAlpha: Bool
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let nsImage = NSImage(data: imageData) {
                // Image display with zoom
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoomLevel)
                        .frame(maxWidth: .infinity, maxHeight: 500)
                }
                .frame(maxHeight: 500)
                .background(Color(white: 0.95))
                .cornerRadius(8)
                
                // Zoom controls
                HStack {
                    Button(action: { zoomLevel = max(0.25, zoomLevel - 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Text("\(Int(zoomLevel * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60)
                    
                    Button(action: { zoomLevel = min(3.0, zoomLevel + 0.25) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { zoomLevel = 1.0 }) {
                        Text("Fit")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { zoomLevel = 1.0 }) {
                        Text("1:1")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                }
                
                // Image info
                if let info = imageInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Image Information")
                            .font(.headline)
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Dimensions:")
                                    .foregroundColor(.secondary)
                                Text("\(Int(info.size.width)) × \(Int(info.size.height)) px")
                            }
                            
                            GridRow {
                                Text("File Size:")
                                    .foregroundColor(.secondary)
                                Text(formatFileSize(info.fileSize))
                            }
                            
                            GridRow {
                                Text("Format:")
                                    .foregroundColor(.secondary)
                                Text(info.format)
                            }
                            
                            if let colorSpace = info.colorSpace {
                                GridRow {
                                    Text("Color Space:")
                                        .foregroundColor(.secondary)
                                    Text(colorSpace)
                                }
                            }
                            
                            GridRow {
                                Text("Has Alpha:")
                                    .foregroundColor(.secondary)
                                Text(info.hasAlpha ? "Yes" : "No")
                            }
                        }
                        .font(.caption)
                    }
                    .padding(12)
                    .background(Color(white: 0.95))
                    .cornerRadius(8)
                }
            } else {
                Text("Unable to load image")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadImageInfo()
        }
    }
    
    private func loadImageInfo() {
        guard let nsImage = NSImage(data: imageData),
              let imageRep = nsImage.representations.first else {
            return
        }
        
        let size = imageRep.size
        let fileSize = imageData.count
        
        var format = "Unknown"
        var colorSpace: String? = nil
        var hasAlpha = false
        
        if let bitmapRep = imageRep as? NSBitmapImageRep {
            format = bitmapRep.bitmapFormat.contains(.alphaFirst) || bitmapRep.bitmapFormat.contains(.alphaNonpremultiplied) ? "PNG" : "JPEG"
            // Get color space name
            colorSpace = bitmapRep.colorSpace.localizedName
            hasAlpha = bitmapRep.hasAlpha
        } else if imageRep is NSPDFImageRep {
            format = "PDF"
        }
        
        // Try to detect format from data
        if format == "Unknown" {
            if imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                format = "PNG"
            } else if imageData.starts(with: [0xFF, 0xD8, 0xFF]) {
                format = "JPEG"
            } else if imageData.starts(with: [0x47, 0x49, 0x46]) {
                format = "GIF"
            } else if imageData.starts(with: [0x52, 0x49, 0x46, 0x46]) {
                format = "WebP"
            }
        }
        
        imageInfo = ImageInfo(
            size: size,
            fileSize: fileSize,
            format: format,
            colorSpace: colorSpace,
            hasAlpha: hasAlpha
        )
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

