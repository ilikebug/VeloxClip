import SwiftUI
import Foundation

struct PreviewView: View {
    let item: ClipboardItem?
    @ObservedObject var store = ClipboardStore.shared
    @StateObject private var viewModel = PreviewViewModel()
    @State private var debouncedItem: ClipboardItem?
    @State private var debounceTask: Task<Void, Never>?
    
    @State private var showErrorDetails = false
    
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
                ContentUnavailableView("Select an Item", systemImage: "paperclip", description: Text("Choose a clip from the history to preview its content."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if !Task.isCancelled {
                await MainActor.run {
                    debouncedItem = newItem
                    viewModel.updateItem(newItem)
                }
            }
        }
    }
    
    @ViewBuilder
    private func headerView(for displayItem: ClipboardItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayItem.type.capitalized)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .kerning(1.2)
                
                Text(displayItem.sourceApp ?? "System")
                    .font(.title3.bold())
            }
            
            Spacer()
            
            favoriteButton(for: displayItem)
            
            if viewModel.isAIProcessing {
                processingIndicator
            } else if let error = viewModel.aiError {
                errorIndicator(error)
            }
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(displayItem.createdAt, style: .date)
                Text(displayItem.createdAt, style: .time)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(DesignSystem.primaryGradient.opacity(0.1))
    }
    
    @ViewBuilder
    private func favoriteButton(for displayItem: ClipboardItem) -> some View {
        Button(action: { store.toggleFavorite(for: displayItem) }) {
            Image(systemName: displayItem.isFavorite ? "star.fill" : "star")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(displayItem.isFavorite ? AnyShapeStyle(DesignSystem.primaryGradient) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
    }
    
    private var processingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Thinking...").font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1)).cornerRadius(12)
    }
    
    @ViewBuilder
    private func errorIndicator(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text("AI Error").font(.caption).foregroundColor(.orange)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.orange.opacity(0.1)).cornerRadius(12)
        .onTapGesture { showErrorDetails = true }
        .popover(isPresented: $showErrorDetails) {
            errorPopover(error)
        }
    }
    
    @ViewBuilder
    private func errorPopover(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Service Error").font(.headline)
            ScrollView {
                Text(error).font(.caption.monospaced()).textSelection(.enabled)
            }
            .frame(maxHeight: 300)
            Button("Dismiss") { viewModel.aiError = nil; showErrorDetails = false }
        }
        .padding().frame(width: 300)
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
        VStack(spacing: 12) {
            ProgressView().scaleEffect(0.8)
            Text("Detecting content...").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    
    @ViewBuilder
    private func renderPreview(for item: ClipboardItem) -> some View {
        switch viewModel.detectedType {
        case .image:
            if let data = item.data {
                ScrollView([.horizontal, .vertical]) {
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
        if let ocrText = item.content, !ocrText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.viewfinder").foregroundColor(.blue)
                    Text("OCR Text").font(.headline)
                    Button("Copy") { viewModel.copyTransformedText(ocrText) }
                    Spacer()
                }
                Text(ocrText).font(.system(.body, design: .monospaced))
                    .padding(8).background(Color.secondary.opacity(0.1)).cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private func plainTextPreview(content: String) -> some View {
        let maxChars = 5000
        let displayContent = content.count > maxChars ? String(content.prefix(maxChars)) : content
        VStack(alignment: .leading, spacing: 8) {
            Text(displayContent).font(.body).lineLimit(nil)
            if content.count > maxChars {
                Text("... (\(content.count - maxChars) more characters)")
                    .font(.caption).foregroundColor(.secondary).italic()
            }
        }
    }
    
    @ViewBuilder
    private func actionsToolbar(for item: ClipboardItem) -> some View {
        HStack {
            Button(action: { viewModel.copyToClipboard(item) }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            
            if item.type == "image", let imageData = item.data, let nsImage = NSImage(data: imageData) {
                Button(action: { ScreenshotEditorService.shared.showEditor(with: nsImage) }) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }
            
            magicActionsMenu(for: item)
            Spacer()
        }
        .padding().background(Color.black.opacity(0.02))
    }
    
    @ViewBuilder
    private func magicActionsMenu(for item: ClipboardItem) -> some View {
        Menu {
            if let content = item.content {
                Section("AI Actions") {
                    ForEach(AIAction.allCases) { action in
                        Button {
                            Task { await viewModel.performAIAction(action, content: content) }
                        } label: { Label(action.rawValue, systemImage: action.icon) }
                    }
                }
                Section("Tools") {
                    standardTextTools(content: content)
                }
            }
        } label: {
            Label("Magic", systemImage: "wand.and.stars")
        }
        .menuStyle(.button).disabled(viewModel.isAIProcessing)
    }
    
    @ViewBuilder
    private func standardTextTools(content: String) -> some View {
        Group {
            Button("UPPERCASE") { viewModel.copyTransformedText(AIService.shared.convertCase(content, to: .uppercase)) }
            Button("lowercase") { viewModel.copyTransformedText(AIService.shared.convertCase(content, to: .lowercase)) }
            Button("Cleanup") { viewModel.copyTransformedText(AIService.shared.cleanupText(content)) }
        }
    }
    
    @ViewBuilder
    private func tagsSection(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Button(action: { isEditingTags.toggle(); isTagInputFocused = isEditingTags }) {
                    Image(systemName: isEditingTags ? "checkmark.circle.fill" : "plus.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(item.tags, id: \.self) { tag in
                        tagView(tag: tag, item: item)
                    }
                    if isEditingTags {
                        tagInputField(for: item)
                    }
                    if !isEditingTags && item.tags.isEmpty {
                        Text("No tags").font(.caption).foregroundColor(.secondary).italic()
                    }
                }
                .padding(.horizontal).padding(.bottom, 8)
            }
        }
    }
    
    @ViewBuilder
    private func tagView(tag: String, item: ClipboardItem) -> some View {
        HStack(spacing: 4) {
            Text(tag)
            if isEditingTags {
                Button(action: { store.removeTag(tag, from: item) }) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tagColor(for: tag)).foregroundColor(.white).cornerRadius(6)
    }
    
    @ViewBuilder
    private func tagInputField(for item: ClipboardItem) -> some View {
        TextField("New tag...", text: $newTagText)
            .textFieldStyle(.plain)
            .font(.caption)
            .frame(width: 80)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1)).cornerRadius(4)
            .focused($isTagInputFocused)
            .onSubmit {
                if !newTagText.isEmpty {
                    store.addTag(newTagText, to: item)
                    newTagText = ""
                }
            }
    }
    
    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan]
        let hash = abs(tag.hashValue)
        return colors[hash % colors.count]
    }
}

