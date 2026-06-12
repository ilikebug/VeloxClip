import SwiftUI
import SwiftData

struct ClipboardListView: View {
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var pasteStack = PasteStackService.shared
    @Binding var selectedItem: ClipboardItem?
    var items: [ClipboardItem] // Use items passed from parent instead of computing here
    // Set by keyboard navigation only — mouse clicks must not auto-scroll the list,
    // or rows shift under the cursor and selection feels janky
    @Binding var scrollTarget: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedItem) {
                ForEach(items) { item in
                    ClipboardItemRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        stagedIndex: pasteStack.stagedIndex(of: item.id),
                        onSelect: {
                            selectedItem = item
                        },
                        onDoubleClick: {
                            WindowManager.shared.selectAndPaste(item)
                        },
                        onToggleStage: {
                            pasteStack.toggleStaged(item)
                        }
                    )
                    .tag(item)
                    .id(item.id)
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.sidebar)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                scrollTarget = nil
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        Task {
            await store.deleteItems(at: offsets, in: items)
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let stagedIndex: Int?
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onToggleStage: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            if item.type == "image" {
                ImageRowThumbnail(itemID: item.id, fallbackColor: typeColor(for: item.type))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(typeColor(for: item.type).opacity(0.15))
                        .frame(width: 36, height: 36)

                    typeIcon(for: item.type)
                        .foregroundColor(typeColor(for: item.type))
                        .font(.system(size: 16, weight: .semibold))
                }
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

            Spacer()

            if let stagedIndex {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                    Text("\(stagedIndex + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .onTapGesture { onToggleStage() }
                .help("In paste queue — click to remove")
            } else if isHovering {
                Button(action: onToggleStage) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add to paste queue (Space)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // Selection is handled by our own gestures: the gesture layer covers the whole
        // row (contentShape), so List's native click-selection never sees the click.
        // Both gestures are simultaneous — the first click of a double-click selects
        // immediately (no double-click disambiguation delay), the second fires paste.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onDoubleClick()
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                onSelect()
            }
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
        if item.type == "file", let content = item.content {
            let paths = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let firstName = URL(fileURLWithPath: paths.first ?? content).lastPathComponent
            if paths.count > 1 {
                return "\(paths.count) files — \(firstName), …"
            }
            return firstName
        }
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
}

// Thumbnail for image rows — decodes lazily via ThumbnailProvider and shows
// the type icon as a placeholder until (or in case) decoding fails
struct ImageRowThumbnail: View {
    let itemID: UUID
    let fallbackColor: Color

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fallbackColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: "photo")
                        .foregroundColor(fallbackColor)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .task(id: itemID) {
            if thumbnail == nil {
                thumbnail = await ThumbnailProvider.shared.thumbnail(for: itemID)
            }
        }
    }
}
