import SwiftUI
import SwiftData

enum EmptyKind {
    case historyEmpty, noMatch, favoritesEmpty

    var icon: String {
        switch self {
        case .historyEmpty:   return "doc.on.clipboard"
        case .noMatch:        return "magnifyingglass"
        case .favoritesEmpty: return "star"
        }
    }
    var title: String {
        switch self {
        case .historyEmpty:   return "还没有剪贴记录"
        case .noMatch:        return "无匹配"
        case .favoritesEmpty: return "还没有收藏"
        }
    }
    var subtitle: String {
        switch self {
        case .historyEmpty:   return "复制点什么，这里就会出现"
        case .noMatch:        return "试别的词，或切到收藏"
        case .favoritesEmpty: return "在详情里点 ★ 收藏常用项"
        }
    }
}

struct ClipboardListView: View {
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var pasteStack = PasteStackService.shared
    @Binding var selectedItem: ClipboardItem?
    var items: [ClipboardItem] // Use items passed from parent instead of computing here
    // Set by keyboard navigation only — mouse clicks must not auto-scroll the list,
    // or rows shift under the cursor and selection feels janky
    @Binding var scrollTarget: UUID?
    var emptyKind: EmptyKind

    var body: some View {
        if items.isEmpty {
            EmptyStateView(icon: emptyKind.icon, title: emptyKind.title, subtitle: emptyKind.subtitle)
        } else {
            ScrollViewReader { proxy in
            List(selection: $selectedItem) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ClipboardItemRow(
                        item: item,
                        index: index,
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
            // .plain is the most neutral, version-stable list chrome; .sidebar's
            // selection highlight / insets were redrawn across macOS releases.
            // Selection is shown by the row's own background, so hide the system
            // scroll background to keep the list looking identical everywhere.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                scrollTarget = nil
            }
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
    let index: Int
    let isSelected: Bool
    let stagedIndex: Int?
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onToggleStage: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        let c = DSColors(scheme: scheme)
        HStack(spacing: 12) {
            rowIcon(c: c)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayContent(for: item))
                    .lineLimit(1)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : c.text)

                Text(RowPresentation.subtitle(type: item.type, content: item.content, tags: item.tags))
                    .lineLimit(1)
                    .font(.system(size: 11.5))
                    .foregroundColor(isSelected ? Color.white.opacity(0.8) : c.text2)
            }

            Spacer()

            Text(RowPresentation.relativeTime(item.lastUsedAt ?? item.createdAt, now: Date()))
                .font(.system(size: 11))
                .foregroundColor(isSelected ? Color.white.opacity(0.75) : c.text3)

            if let stagedIndex {
                ZStack {
                    Circle()
                        .fill(c.accent)
                        .frame(width: 20, height: 20)
                    Text("\(stagedIndex + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .onTapGesture { onToggleStage() }
                .help("已在粘贴队列 — 点击移除")
            } else if isHovering {
                Button(action: onToggleStage) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? .white : c.text2)
                }
                .buttonStyle(.plain)
                .help("加入粘贴队列（Space）")
            } else if isSelected {
                DSKeyBadge(label: "⏎", onAccent: true)
            } else if index < 9 {
                DSKeyBadge(label: "⌘\(index + 1)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? c.accent : (isHovering ? c.hover : Color.clear))
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
    
    // 26×26 content-aware leading icon (kit spec): color swatch, image thumbnail,
    // or a `c.chip` square with a monochrome SF Symbol glyph.
    @ViewBuilder
    private func rowIcon(c: DSColors) -> some View {
        let kind = RowPresentation.iconKind(type: item.type, tags: item.tags)
        switch kind {
        case .image:
            ImageRowThumbnail(itemID: item.id, fallbackColor: c.text2)
        case .color:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: ColorFormatting.hex(from: item.content ?? "") ?? "") ?? c.chip)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(c.divider, lineWidth: 0.5)
                )
        default:
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(c.chip)
                    .frame(width: 26, height: 26)
                Image(systemName: glyph(for: kind))
                    .font(.system(size: 13))
                    .foregroundColor(c.text2)
            }
        }
    }

    private func glyph(for kind: RowIconKind) -> String {
        switch kind {
        case .url:   return "link"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        case .json:  return "curlybraces"
        case .file:  return "folder"
        case .rtf:   return "doc.richtext"
        case .text:  return "textformat"
        case .color, .image: return "textformat" // handled above; unreachable
        }
    }

    private func displayContent(for item: ClipboardItem) -> String {
        if item.type == "color" {
            return ColorFormatting.hex(from: item.content ?? "") ?? (item.content ?? "颜色")
        }
        if item.type == "file", let content = item.content {
            let paths = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let firstName = URL(fileURLWithPath: paths.first ?? content).lastPathComponent
            if paths.count > 1 {
                return "\(paths.count) 个文件 — \(firstName)…"
            }
            return firstName
        }
        if let content = item.content {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if item.type == "image" {
            return "图片数据"
        }
        if item.type == "rtf" {
            return "富文本"
        }
        return "未知内容"
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
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fallbackColor.opacity(0.15))
                        .frame(width: 26, height: 26)

                    Image(systemName: "photo")
                        .foregroundColor(fallbackColor)
                        .font(.system(size: 13))
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
