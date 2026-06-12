import SwiftUI
import AppKit

// Entry point: a file item stores one path per line — a multi-file copy
// stays ONE history item (paste reproduces the whole group), the preview
// just adapts to show either a single file or the file list
struct FilePreviewView: View {
    let filePath: String

    private var paths: [String] {
        filePath.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if paths.count > 1 {
            MultiFilePreview(paths: paths)
        } else {
            SingleFilePreview(filePath: paths.first ?? filePath)
        }
    }
}

// MARK: - Multi-file list

struct MultiFilePreview: View {
    let paths: [String]
    @State private var entries: [FileEntry] = []

    struct FileEntry: Identifiable {
        let id = UUID()
        let path: String
        let name: String
        let exists: Bool
        let size: Int64
        let isDirectory: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary header
            HStack(spacing: 16) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entries.count) Files")
                        .font(.title3.bold())
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // File rows
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    fileRow(entry)
                    if index < entries.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
        .onAppear {
            loadEntries()
        }
    }

    private var summaryLine: String {
        let existing = entries.filter(\.exists)
        let totalSize = existing.reduce(Int64(0)) { $0 + $1.size }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file

        var parts = [formatter.string(fromByteCount: totalSize)]
        let missingCount = entries.count - existing.count
        if missingCount > 0 {
            parts.append("\(missingCount) missing")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func fileRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .font(.system(size: 18))
                .foregroundColor(entry.exists ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .textSelection(.enabled)
                Text(entry.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            Spacer()

            if entry.exists {
                Text(formatFileSize(entry.size))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { revealInFinder(entry) }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                Button(action: { copySingleFile(entry) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy just this file")
            } else {
                Text("Missing")
                    .font(.caption.bold())
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func loadEntries() {
        let fileManager = FileManager.default
        entries = paths.map { path in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            var size: Int64 = 0
            if exists, let attributes = try? fileManager.attributesOfItem(atPath: path),
               let fileSize = attributes[.size] as? Int64 {
                size = fileSize
            }
            return FileEntry(
                path: path,
                name: URL(fileURLWithPath: path).lastPathComponent,
                exists: exists,
                size: size,
                isDirectory: isDirectory.boolValue
            )
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func revealInFinder(_ entry: FileEntry) {
        NSWorkspace.shared.selectFile(
            entry.path,
            inFileViewerRootedAtPath: URL(fileURLWithPath: entry.path).deletingLastPathComponent().path
        )
    }

    // "I only want this one out of the group" — covers the only real advantage
    // splitting into separate history items would have had
    private func copySingleFile(_ entry: FileEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if entry.exists, pasteboard.writeObjects([URL(fileURLWithPath: entry.path) as NSURL]) {
            return
        }
        pasteboard.setString(entry.path, forType: .string)
    }
}

// MARK: - Single file

struct SingleFilePreview: View {
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
                            .textSelection(.enabled)

                        Text(info.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
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
                .textSelection(.enabled)
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

