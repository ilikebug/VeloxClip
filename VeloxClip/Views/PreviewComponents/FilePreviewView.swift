import SwiftUI
import AppKit

// File preview with file info
struct FilePreviewView: View {
    let filePath: String
    @State private var fileInfo: FileInfo?
    
    struct FileInfo {
        let name: String
        let path: String
        let size: Int64
        let type: String
        let exists: Bool
        let modifiedDate: Date?
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info = fileInfo {
                // File icon and name
                HStack(spacing: 16) {
                    Image(systemName: fileIcon(for: info.type))
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.name)
                            .font(.title3.bold())
                        
                        Text(info.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                
                // File info
                if info.exists {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("File Details")
                            .font(.headline)
                        
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                            fileInfoRow(label: "Size", value: formatFileSize(info.size))
                            fileInfoRow(label: "Type", value: info.type)
                            if let modified = info.modifiedDate {
                                fileInfoRow(label: "Modified", value: "\(modified.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                    
                    // Actions
                    HStack {
                        Button(action: openFile) {
                            Label("Open File", systemImage: "doc")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(action: revealInFinder) {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: copyPath) {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: copyName) {
                            Label("Copy Name", systemImage: "text")
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("File does not exist")
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            loadFileInfo()
        }
    }
    
    private func fileInfoRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
        }
    }
    
    private func loadFileInfo() {
        let url = URL(fileURLWithPath: filePath)
        let name = url.lastPathComponent
        let path = url.path
        
        var exists = false
        var size: Int64 = 0
        var type = "Unknown"
        var modifiedDate: Date?
        
        if FileManager.default.fileExists(atPath: path) {
            exists = true
            
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                if let fileSize = attributes[.size] as? Int64 {
                    size = fileSize
                }
                if let modDate = attributes[.modificationDate] as? Date {
                    modifiedDate = modDate
                }
            }
            
            // Get file type
            if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
                type = uti
            } else {
                let pathExtension = url.pathExtension.lowercased()
                type = pathExtension.isEmpty ? "File" : pathExtension.uppercased() + " File"
            }
        }
        
        fileInfo = FileInfo(
            name: name,
            path: path,
            size: size,
            type: type,
            exists: exists,
            modifiedDate: modifiedDate
        )
    }
    
    private func fileIcon(for type: String) -> String {
        if type.contains("image") {
            return "photo"
        } else if type.contains("video") {
            return "video"
        } else if type.contains("audio") {
            return "music.note"
        } else if type.contains("pdf") {
            return "doc.fill"
        } else if type.contains("text") {
            return "doc.text"
        } else if type.contains("folder") || type.contains("directory") {
            return "folder"
        } else {
            return "doc"
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func openFile() {
        let url = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.open(url)
    }
    
    private func revealInFinder() {
        let url = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(filePath, forType: .string)
    }
    
    private func copyName() {
        guard let info = fileInfo else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info.name, forType: .string)
    }
}

