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
                    Text(DateTimePreviewPresentation.title)
                        .font(.dsHeadline)
                        .padding(.bottom, 4)
                    
                    VStack(spacing: 8) {
                        ForEach(Array(formats.enumerated()), id: \.offset) { index, format in
                            HStack {
                                Text(format.name)
                                    .font(.dsCaption.bold())
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)

                                Text(format.value)
                                    .font(.dsMonoBody)
                                    .textSelection(.enabled)
                                
                                Spacer()
                                
                                Button(action: { copyFormat(format.value) }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.dsCaption)
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
                        Label(DateTimePreviewPresentation.copyISOButtonTitle, systemImage: "doc.on.doc")
                    }
                    .dsButton()

                    Button(action: { copyUnixTimestamp() }) {
                        Label(DateTimePreviewPresentation.copyUnixButtonTitle, systemImage: "number")
                    }
                    .dsButton()

                    Button(action: { copyAllFormats() }) {
                        Label(DateTimePreviewPresentation.copyAllButtonTitle, systemImage: "doc.on.doc.fill")
                    }
                    .dsButton()
                    
                    Spacer()
                }
            } else {
                Text(dateString)
                    .font(.dsBody)
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
            DateFormat(name: "Unix 时间戳", value: String(Int(date.timeIntervalSince1970))),
            DateFormat(name: "相对时间", value: relativeTimeString(from: date)),
            DateFormat(name: "易读格式", value: humanReadableString(from: date)),
            DateFormat(name: "仅日期", value: DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)),
            DateFormat(name: "仅时间", value: DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)),
            DateFormat(name: "完整格式", value: DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .full)),
            DateFormat(name: "短格式", value: DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))
        ]
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        return DateTimePreviewPresentation.relativeTime(secondsAgo: interval)
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
