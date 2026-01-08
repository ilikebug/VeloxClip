import SwiftUI
import AppKit

// Date/Time preview with multiple formats
struct DateTimePreviewView: View {
    let dateString: String
    @State private var parsedDate: Date?
    @State private var formats: [DateFormat] = []
    
    struct DateFormat {
        let name: String
        let value: String
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if parsedDate != nil {
                // Date display
                VStack(alignment: .leading, spacing: 12) {
                    Text("Date/Time Formats")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    VStack(spacing: 8) {
                        ForEach(Array(formats.enumerated()), id: \.offset) { index, format in
                            HStack {
                                Text(format.name)
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                
                                Text(format.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                
                                Spacer()
                                
                                Button(action: { copyFormat(format.value) }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            if index < formats.count - 1 {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                
                // Quick actions
                HStack {
                    Button(action: { copyFormat(formats.first?.value ?? "") }) {
                        Label("Copy ISO", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { copyUnixTimestamp() }) {
                        Label("Copy Unix", systemImage: "number")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { copyAllFormats() }) {
                        Label("Copy All", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
            } else {
                Text(dateString)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .onAppear {
            parseDate()
        }
    }
    
    private func parseDate() {
        // Try multiple date formats
        let formatters: [DateFormatter] = [
            createFormatter(format: "yyyy-MM-dd HH:mm:ss"),
            createFormatter(format: "yyyy-MM-dd'T'HH:mm:ssZ"),
            createFormatter(format: "yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
            createFormatter(format: "yyyy-MM-dd"),
            createFormatter(format: "MM/dd/yyyy"),
            createFormatter(format: "dd/MM/yyyy"),
            createFormatter(format: "EEE, dd MMM yyyy HH:mm:ss Z"),
            createFormatter(format: "dd MMM yyyy HH:mm:ss")
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                parsedDate = date
                generateFormats(date: date)
                return
            }
        }
        
        // Try Unix timestamp
        if let timestamp = Double(dateString.trimmingCharacters(in: .whitespaces)) {
            let date = Date(timeIntervalSince1970: timestamp)
            parsedDate = date
            generateFormats(date: date)
            return
        }
        
        parsedDate = nil
    }
    
    private func createFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
    
    private func generateFormats(date: Date) {
        formats = [
            DateFormat(name: "ISO 8601", value: ISO8601DateFormatter().string(from: date)),
            DateFormat(name: "Unix Timestamp", value: String(Int(date.timeIntervalSince1970))),
            DateFormat(name: "Relative", value: relativeTimeString(from: date)),
            DateFormat(name: "Human Readable", value: humanReadableString(from: date)),
            DateFormat(name: "Date Only", value: DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)),
            DateFormat(name: "Time Only", value: DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)),
            DateFormat(name: "Full", value: DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .full)),
            DateFormat(name: "Short", value: DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))
        ]
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "\(Int(interval)) seconds ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60)) minutes ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600)) hours ago"
        } else if interval < 604800 {
            return "\(Int(interval / 86400)) days ago"
        } else {
            return "\(Int(interval / 604800)) weeks ago"
        }
    }
    
    private func humanReadableString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func copyFormat(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
    
    private func copyUnixTimestamp() {
        guard let date = parsedDate else { return }
        copyFormat(String(Int(date.timeIntervalSince1970)))
    }
    
    private func copyAllFormats() {
        let allFormats = formats.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        copyFormat(allFormats)
    }
}

