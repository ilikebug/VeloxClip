import SwiftUI
import AppKit

// JSON preview with formatting and validation
struct JSONPreviewView: View {
    let jsonString: String
    @State private var formattedJSON: String = ""
    @State private var minifiedJSONText: String = ""
    @State private var isValidJSON = false
    @State private var validationError: String?
    @State private var viewMode: ViewMode = .formatted
    @State private var showTreeView = false
    
    enum ViewMode {
        case formatted, minified, tree
    }
    
    @State private var isLoading = true
    
    // Static cache for processed JSON to persist across view updates
    static var jsonCache: [String: (formatted: String, minified: String, isValid: Bool, error: String?)] = [:]
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                header.padding(.horizontal, 16)
                contentArea(availableWidth: geo.size.width)
            }
        }
        .task(id: jsonString) {
            await validateAndFormatAsync()
        }
    }
    
    private var header: some View {
        HStack {
            validationStatus
            Spacer()
            if !isLoading {
                Picker("View", selection: $viewMode) {
                    Text("Formatted").tag(ViewMode.formatted)
                    Text("Minified").tag(ViewMode.minified)
                    Text("Tree").tag(ViewMode.tree)
                }
                .pickerStyle(.segmented).frame(width: 200)
                
                Button(action: copyJSON) { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var validationStatus: some View {
        if isLoading {
            ProgressView().scaleEffect(0.7)
            Text("Validating...").font(.caption).foregroundColor(.secondary)
        } else if isValidJSON {
            Label("Valid JSON", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
        } else if let error = validationError {
            Label("Invalid JSON", systemImage: "xmark.circle.fill").font(.caption).foregroundColor(.red).help(error)
        }
    }
    
    private func contentArea(availableWidth: CGFloat) -> some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    loadingSpinner
                } else if isValidJSON {
                    switch viewMode {
                    case .formatted: formattedView
                    case .minified: minifiedView
                    case .tree: treeView
                    }
                } else {
                    errorView
                }
            }
            .padding(.vertical, 12)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: availableWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .scrollIndicators(.visible)
    }

    private var loadingSpinner: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading JSON...").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    private var formattedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            let lines = formattedJSON.components(separatedBy: .newlines)
            ForEach(0..<lines.count, id: \.self) { i in
                Text(lines[i])
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 40)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var minifiedView: some View {
        Text(minifiedJSONText)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .textSelection(.enabled)
            .padding(12)
            .padding(.trailing, 40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var treeView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let jsonObject = parseJSON() {
                JSONTreeView(jsonObject: jsonObject, level: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var errorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JSON Validation Error:").font(.headline).foregroundColor(.red)
            if let error = validationError {
                Text(error).font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
            }
            Divider()
            Text("Raw Content:").font(.caption).foregroundColor(.secondary)
            Text(jsonString).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
        .padding(12)
    }
    
    private func validateAndFormatAsync() async {
        isLoading = true
        let input = jsonString
        
        if let cached = Self.jsonCache[input] {
            self.formattedJSON = cached.formatted
            self.minifiedJSONText = cached.minified
            self.isValidJSON = cached.isValid
            self.validationError = cached.error
            self.isLoading = false
            return
        }
        
        await Task.detached(priority: .userInitiated) {
            guard let data = input.data(using: .utf8) else {
                await MainActor.run {
                    self.isValidJSON = false
                    self.validationError = "Invalid UTF-8 encoding"
                    self.isLoading = false
                }
                return
            }
            
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                let formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
                let minifiedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
                
                let formatted = String(data: formattedData, encoding: .utf8) ?? ""
                let minified = String(data: minifiedData, encoding: .utf8) ?? ""
                
                await MainActor.run {
                    if Self.jsonCache.count >= 100 {
                        Self.jsonCache.removeValue(forKey: Self.jsonCache.keys.first!)
                    }
                    Self.jsonCache[input] = (formatted, minified, true, nil)
                    
                    self.formattedJSON = formatted
                    self.minifiedJSONText = minified
                    self.isValidJSON = true
                    self.validationError = nil
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    if Self.jsonCache.count >= 100 {
                        Self.jsonCache.removeValue(forKey: Self.jsonCache.keys.first!)
                    }
                    Self.jsonCache[input] = ("", "", false, error.localizedDescription)
                    
                    self.isValidJSON = false
                    self.validationError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }.value
    }
    
    private func parseJSON() -> Any? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    
    private func copyJSON() {
        let text = viewMode == .minified ? minifiedJSONText : formattedJSON
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}


// Tree view for JSON
struct JSONTreeView: View {
    let jsonObject: Any
    let level: Int
    @State private var isExpanded = true
    
    // Lazy loading state for dictionaries and arrays
    @State private var loadedKeys: [String] = []
    @State private var loadedArrayItems: [(Int, Any)] = []
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var isLoadingMore = false
    
    private let indent: CGFloat = 20
    private let itemsPerPage = 20
    
    var body: some View {
        Group {
            if let dict = jsonObject as? [String: Any] {
                dictionaryView(dict)
            } else if let array = jsonObject as? [Any] {
                arrayView(array)
            } else {
                valueView(jsonObject)
            }
        }
        .onAppear {
            if let dict = jsonObject as? [String: Any], loadedKeys.isEmpty {
                loadInitialKeys(from: dict)
            } else if let array = jsonObject as? [Any], loadedArrayItems.isEmpty {
                loadInitialArrayItems(from: array)
            }
        }
    }
    
    private func loadInitialKeys(from dict: [String: Any]) {
        let sortedKeys = Array(dict.keys.sorted())
        let initialCount = min(itemsPerPage, sortedKeys.count)
        loadedKeys = Array(sortedKeys.prefix(initialCount))
    }
    
    private func loadInitialArrayItems(from array: [Any]) {
        let initialCount = min(itemsPerPage, array.count)
        loadedArrayItems = Array(array.enumerated().prefix(initialCount))
    }
    
    private func dictionaryView(_ dict: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("{")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
                
                Text("\(dict.count) keys")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(loadedKeys, id: \.self) { key in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\"\(key)\":")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.purple)
                            
                            JSONTreeView(jsonObject: dict[key]!, level: level + 1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.leading, indent)
                    }
                    
                    if loadedKeys.count < dict.count {
                        loadMoreIndicator
                            .onAppear {
                                loadMoreKeys(from: dict)
                            }
                            .padding(.leading, indent)
                    }
                }
                
                Text("}")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
            } else {
                Text("...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, indent)
            }
        }
    }
    
    private func arrayView(_ array: [Any]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("[")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
                
                Text("\(array.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(loadedArrayItems, id: \.0) { index, item in
                        HStack(alignment: .top, spacing: 4) {
                            Text("[\(index)]:")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.orange)
                            
                            JSONTreeView(jsonObject: item, level: level + 1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.leading, indent)
                    }
                    
                    if loadedArrayItems.count < array.count {
                        loadMoreIndicator
                            .onAppear {
                                loadMoreArrayItems(from: array)
                            }
                            .padding(.leading, indent)
                    }
                }
                
                Text("]")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
            } else {
                Text("...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, indent)
            }
        }
    }
    
    private var loadMoreIndicator: some View {
        HStack {
            if isLoadingMore {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Loading...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func loadMoreKeys(from dict: [String: Any]) {
        guard !isLoadingMore && loadedKeys.count < dict.count else { return }
        
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            isLoadingMore = true
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            if !Task.isCancelled {
                await MainActor.run {
                    let sortedKeys = Array(dict.keys.sorted())
                    let nextCount = min(loadedKeys.count + itemsPerPage, sortedKeys.count)
                    loadedKeys = Array(sortedKeys.prefix(nextCount))
                    isLoadingMore = false
                }
            } else {
                isLoadingMore = false
            }
        }
    }
    
    private func loadMoreArrayItems(from array: [Any]) {
        guard !isLoadingMore && loadedArrayItems.count < array.count else { return }
        
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            isLoadingMore = true
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            if !Task.isCancelled {
                await MainActor.run {
                    let nextCount = min(loadedArrayItems.count + itemsPerPage, array.count)
                    loadedArrayItems = Array(array.enumerated().prefix(nextCount))
                    isLoadingMore = false
                }
            } else {
                isLoadingMore = false
            }
        }
    }
    
    private func valueView(_ value: Any) -> some View {
        let valueString: String
        let color: Color
        
        if value is String {
            valueString = "\"\(value)\""
            color = .green
        } else if value is Bool {
            valueString = "\(value)"
            color = .orange
        } else if value is NSNull {
            valueString = "null"
            color = .gray
        } else {
            valueString = "\(value)"
            color = .blue
        }
        
        return Text(valueString)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(color)
    }
}

