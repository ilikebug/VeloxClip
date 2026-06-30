import SwiftUI
import Foundation

struct PreviewSurfaceStyle {
    static let usesOpaqueWindowBackground = true
}

struct PreviewView: View {
    @Environment(\.colorScheme) private var scheme
    let item: ClipboardItem?
    /// When non-nil, the header renders a leading ‹ 返回 button (push-in detail mode).
    var onBack: (() -> Void)? = nil
    /// When non-nil, the header renders a trailing ✕ 关闭 button (push-in detail mode).
    var onClose: (() -> Void)? = nil
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var viewModel = PreviewViewModel()
    @State private var debouncedItem: ClipboardItem?
    @State private var debounceTask: Task<Void, Never>?

    // Tag editing state
    @State private var isEditingTags = false
    @State private var newTagText = ""
    @FocusState private var isTagInputFocused: Bool
    
    // Get the latest item from store to ensure favorite status is up to date
    private var currentItem: ClipboardItem? {
        guard let item = item else { return nil }
        return store.items.first(where: { $0.id == item.id }) ?? item
    }
    
    var body: some View {
        Group {
            if let item = debouncedItem {
                let displayItem = currentItem ?? item
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    headerView(for: displayItem)
                    
                    // Tags Section
                    tagsSection(for: displayItem)
                    
                    Divider()
                    
                    // Main Preview Content
                    previewScrollContent(for: item)
                    
                    Divider()
                    
                    // Bottom Actions Toolbar
                    actionsToolbar(for: item)
                }
            } else {
                ContentUnavailableView(
                    L10n.string("detail.empty.title", language: settings.appLanguage),
                    systemImage: "paperclip",
                    description: Text(L10n.string("detail.empty.subtitle", language: settings.appLanguage))
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            if PreviewSurfaceStyle.usesOpaqueWindowBackground {
                DSColors(scheme: scheme).window
            }
        }
        .animation(.easeInOut(duration: 0.2), value: debouncedItem?.id)
        .onChange(of: item) { _, newValue in
            handleItemChange(newValue)
        }
        .onAppear {
            handleItemChange(item)
        }
    }
    
    private func handleItemChange(_ newItem: ClipboardItem?) {
        if newItem?.id != debouncedItem?.id {
            isEditingTags = false
            newTagText = ""
        }

        debounceTask?.cancel()

        let isLarge = (newItem?.content?.count ?? 0) > 1000 || newItem?.type == "image"

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: isLarge ? 50_000_000 : 0)
            if Task.isCancelled { return }

            // Blobs are not loaded with the list — fetch on demand for preview
            var resolvedItem = newItem
            if let pending = newItem, pending.data == nil,
               pending.type == "image" || pending.type == "rtf" {
                resolvedItem?.data = await store.loadData(for: pending.id)
            }
            if Task.isCancelled { return }

            await MainActor.run {
                debouncedItem = resolvedItem
                viewModel.updateItem(resolvedItem)
            }
        }
    }
    
    @ViewBuilder
    private func headerView(for displayItem: ClipboardItem) -> some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text(L10n.string("detail.back", language: settings.appLanguage))
                                .font(.system(size: 13))
                        }
                        .foregroundColor(c.text2)
                    }
                    .buttonStyle(.plain)
                }

                Text(displayItem.localizedTypeName(language: settings.appLanguage))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(c.text)
                    .lineLimit(1)

                favoriteButton(for: displayItem)

                Spacer(minLength: 8)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(c.text2)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Text(displayItem.createdAt, style: .date)
                Text(displayItem.createdAt, style: .time)
                if let app = displayItem.sourceApp, !app.isEmpty {
                    Text("·")
                    Text(app).lineLimit(1)
                }
            }
            .font(.system(size: 11))
            .foregroundColor(c.text2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(c.window)
    }

    @ViewBuilder
    private func favoriteButton(for displayItem: ClipboardItem) -> some View {
        let c = DSColors(scheme: scheme)
        Button(action: { store.toggleFavorite(for: displayItem) }) {
            Image(systemName: displayItem.isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(displayItem.isFavorite ? c.accent : c.text2)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func previewScrollContent(for item: ClipboardItem) -> some View {
        Group {
            if viewModel.isContentLoading {
                loadingIndicator
            } else {
                renderPreview(for: item)
                    .id(item.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var loadingIndicator: some View {
        let c = DSColors(scheme: scheme)
        return VStack(spacing: 12) {
            ProgressView().scaleEffect(0.8)
            Text(L10n.string("detail.loading", language: settings.appLanguage))
                .font(.system(size: 11.5))
                .foregroundColor(c.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    
    @ViewBuilder
    private func renderPreview(for item: ClipboardItem) -> some View {
        switch viewModel.detectedType {
        case .image:
            if let data = item.data {
                ScrollView(ImagePreviewLayoutPolicy.detailImage.scrollAxes) {
                    VStack(alignment: .leading, spacing: 0) {
                        ImagePreviewView(imageData: data)
                        ocrSection(for: item)
                            .padding(16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .color:
            if let content = item.content {
                ScrollView {
                    ColorPreviewView(colorString: content)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .file:
            if let content = item.content {
                ScrollView {
                    FilePreviewView(filePath: content)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .url:
            ScrollView {
                URLPreviewView(urlString: item.content ?? "")
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .json:
            JSONPreviewView(jsonString: item.content ?? "")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .table:
            TablePreviewView(content: item.content ?? "")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .datetime:
            ScrollView {
                DateTimePreviewView(dateString: item.content ?? "")
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .code:
            CodePreviewView(code: item.content ?? "")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .longtext:
            ScrollView {
                TextSummaryView(text: item.content ?? "")
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .markdown:
            MarkdownView(markdown: item.content ?? "")
        default:
            ScrollView([.horizontal, .vertical]) {
                plainTextPreview(content: item.content ?? "")
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    @ViewBuilder
    private func ocrSection(for item: ClipboardItem) -> some View {
        let c = DSColors(scheme: scheme)
        if let ocrText = item.content, !ocrText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.viewfinder").foregroundColor(c.accent)
                    Text(L10n.string("detail.ocrText", language: settings.appLanguage))
                        .font(.system(size: 11.5))
                        .foregroundColor(c.text2)
                    Button(L10n.string("command.copy", language: settings.appLanguage)) { viewModel.copyTransformedText(ocrText) }
                        .dsButton(.secondary, small: true)
                    Spacer()
                }
                Text(ocrText).font(.dsMonoBody).foregroundColor(c.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(c.card))
            }
        }
    }

    @ViewBuilder
    private func plainTextPreview(content: String) -> some View {
        let c = DSColors(scheme: scheme)
        let maxChars = 5000
        let displayContent = content.count > maxChars ? String(content.prefix(maxChars)) : content
        VStack(alignment: .leading, spacing: 8) {
            Text(displayContent).font(.dsBody).foregroundColor(c.text).lineLimit(nil)
                .textSelection(.enabled)
            if content.count > maxChars {
                Text(L10n.format("detail.truncated", content.count - maxChars, language: settings.appLanguage))
                    .font(.system(size: 11)).foregroundColor(c.text2).italic()
            }
        }
    }
    
    @ViewBuilder
    private func actionsToolbar(for item: ClipboardItem) -> some View {
        HStack {
            Button(action: { viewModel.copyToClipboard(item) }) {
                Label(L10n.string("command.copy", language: settings.appLanguage), systemImage: "doc.on.doc")
            }
            .dsButton(.prominent)

            if item.type == "image", let imageData = item.data {
                // Decode the NSImage on click, not on every toolbar render
                Button(action: {
                    if let nsImage = NSImage(data: imageData) {
                        ScreenshotEditorService.shared.showEditor(with: nsImage)
                    }
                }) {
                    Label(L10n.string("detail.edit", language: settings.appLanguage), systemImage: "pencil")
                }
                .dsButton()
            }
            
            textToolsMenu(for: item)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(DSColors(scheme: scheme).window)
    }

    @ViewBuilder
    private func textToolsMenu(for item: ClipboardItem) -> some View {
        let c = DSColors(scheme: scheme)
        if let content = item.content {
            Menu {
                standardTextTools(content: content)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                    Text(L10n.string("detail.tools", language: settings.appLanguage))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(c.text2)
                }
                .compactMenuLabel()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
    
    @ViewBuilder
    private func standardTextTools(content: String) -> some View {
        Group {
            Button(TextToolsPresentation.uppercaseButtonTitle(language: settings.appLanguage)) { viewModel.copyTransformedText(AIService.shared.convertCase(content, to: .uppercase)) }
            Button(TextToolsPresentation.lowercaseButtonTitle(language: settings.appLanguage)) { viewModel.copyTransformedText(AIService.shared.convertCase(content, to: .lowercase)) }
            Button(TextToolsPresentation.cleanupWhitespaceButtonTitle(language: settings.appLanguage)) { viewModel.copyTransformedText(AIService.shared.cleanupText(content)) }
        }
    }
    
    @ViewBuilder
    private func tagsSection(for item: ClipboardItem) -> some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("detail.tags", language: settings.appLanguage))
                    .font(.system(size: 11))
                    .foregroundColor(c.text2)
                Spacer()
                Button(action: { isEditingTags.toggle(); isTagInputFocused = isEditingTags }) {
                    Image(systemName: isEditingTags ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundColor(isEditingTags ? c.accent : c.text2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(item.tags, id: \.self) { tag in
                        tagView(tag: tag, item: item)
                    }
                    if isEditingTags {
                        tagInputField(for: item)
                    }
                    if !isEditingTags && item.tags.isEmpty {
                        Text(L10n.string("detail.noTags", language: settings.appLanguage))
                            .font(.system(size: 11))
                            .foregroundColor(c.text2)
                            .italic()
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func tagView(tag: String, item: ClipboardItem) -> some View {
        let c = DSColors(scheme: scheme)
        HStack(spacing: 4) {
            Text(tag)
            if isEditingTags {
                Button(action: { store.removeTag(tag, from: item) }) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 10).fill(c.accentSoft))
        .foregroundColor(c.accent)
    }

    @ViewBuilder
    private func tagInputField(for item: ClipboardItem) -> some View {
        let c = DSColors(scheme: scheme)
        TextField(L10n.string("detail.newTag.placeholder", language: settings.appLanguage), text: $newTagText)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(c.text)
            .frame(width: 80)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 10).fill(c.field))
            .focused($isTagInputFocused)
            .onSubmit {
                if !newTagText.isEmpty {
                    store.addTag(newTagText, to: item)
                    newTagText = ""
                }
            }
    }
}
