import SwiftUI
import SwiftData

struct ClipboardListView: View {
    @ObservedObject var store = ClipboardStore.shared
    @Binding var selectedItem: ClipboardItem?
    var items: [ClipboardItem] // Use items passed from parent instead of computing here
    
    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedItem) {
                ForEach(items) { item in
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(typeColor(for: item.type).opacity(0.15))
                                .frame(width: 36, height: 36)
                            
                            typeIcon(for: item.type)
                                .foregroundColor(typeColor(for: item.type))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayContent(for: item))
                                .lineLimit(1)
                                .font(.system(.body, design: .rounded))
                            
                            HStack {
                                Text(item.sourceApp ?? "Unknown")
                                    .fontWeight(.medium)
                                Text("•")
                                Text(item.createdAt, style: .time)
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer() // Push content to the left
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading) // Fill width
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedItem?.id == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .tag(item)
                    .id(item.id) // Needed for ScrollViewReader
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.sidebar)
            .onChange(of: selectedItem) { newItem in
                if let newItem = newItem {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newItem.id, anchor: .center)
                    }
                }
            }
        }
    }
    
    private func typeColor(for type: String) -> Color {
        switch type {
        case "text": return .blue
        case "image": return .purple
        case "file": return .orange
        case "color": return .green
        case "rtf": return .cyan
        default: return .gray
        }
    }
    
    private func typeIcon(for type: String) -> some View {
        switch type {
        case "text": return Image(systemName: "doc.text")
        case "image": return Image(systemName: "photo")
        case "file": return Image(systemName: "folder")
        case "color": return Image(systemName: "paintpalette")
        case "rtf": return Image(systemName: "doc.richtext")
        default: return Image(systemName: "paperclip")
        }
    }
    
    private func displayContent(for item: ClipboardItem) -> String {
        if let content = item.content {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if item.type == "image" {
            return "Image Data"
        }
        if item.type == "rtf" {
            return "Rich Text"
        }
        return "Unknown Content"
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            store.deleteItems(at: offsets)
        }
    }
}
