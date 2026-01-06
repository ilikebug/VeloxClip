import SwiftUI
import AppKit

// JSON preview with formatting and validation
struct JSONPreviewView: View {
    let jsonString: String
    @State private var formattedJSON: String = ""
    @State private var isValidJSON = false
    @State private var validationError: String?
    @State private var viewMode: ViewMode = .formatted
    @State private var showTreeView = false
    
    enum ViewMode {
        case formatted
        case minified
        case tree
    }
    
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toolbar
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Validating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if isValidJSON {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Valid JSON")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else if let error = validationError {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Invalid JSON")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .help(error)
                }
                
                Spacer()
                
                if !isLoading {
                    Picker("View", selection: $viewMode) {
                        Text("Formatted").tag(ViewMode.formatted)
                        Text("Minified").tag(ViewMode.minified)
                        Text("Tree").tag(ViewMode.tree)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    
                    Button(action: copyJSON) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 8)
            
            // JSON content
            ScrollView(.horizontal, showsIndicators: true) {
                ScrollView(.vertical, showsIndicators: true) {
                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading JSON preview...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if isValidJSON {
                        switch viewMode {
                        case .formatted:
                            formattedView
                        case .minified:
                            minifiedView
                        case .tree:
                            treeView
                        }
                    } else {
                        errorView
                    }
                }
            }
            .frame(maxHeight: 400)
            .background(Color(white: 0.95))
            .cornerRadius(8)
        }
        .task {
            await validateAndFormatAsync()
        }
    }
    
    private var formattedView: some View {
        Text(formattedJSON)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }
    
    private var minifiedView: some View {
        Text(minifiedJSON)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }
    
    private var treeView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let jsonObject = parseJSON() {
                JSONTreeView(jsonObject: jsonObject, level: 0)
            }
        }
        .padding(12)
    }
    
    private var errorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JSON Validation Error:")
                .font(.headline)
                .foregroundColor(.red)
            
            if let error = validationError {
                Text(error)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Text("Raw Content:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(jsonString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(12)
    }
    
    private var minifiedJSON: String {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let minifiedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
              let minified = String(data: minifiedData, encoding: .utf8) else {
            return jsonString
        }
        return minified
    }
    
    private func validateAndFormatAsync() async {
        isLoading = true
        
        // Perform heavy JSON parsing on background thread
        await Task.detached(priority: .userInitiated) { @Sendable () async -> Void in
            guard let data = jsonString.data(using: .utf8) else {
                await MainActor.run {
                    isValidJSON = false
                    validationError = "Invalid UTF-8 encoding"
                    isLoading = false
                }
                return
            }
            
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                let formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
                
                if let formatted = String(data: formattedData, encoding: .utf8) {
                    await MainActor.run {
                        formattedJSON = formatted
                        isValidJSON = true
                        validationError = nil
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        isValidJSON = false
                        validationError = "Failed to format JSON"
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    isValidJSON = false
                    validationError = error.localizedDescription
                    isLoading = false
                }
            }
        }.value
    }
    
    private func parseJSON() -> Any? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    
    private func copyJSON() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let textToCopy: String
        switch viewMode {
        case .formatted:
            textToCopy = formattedJSON
        case .minified:
            textToCopy = minifiedJSON
        case .tree:
            textToCopy = formattedJSON // Tree view copy as formatted
        }
        
        pasteboard.setString(textToCopy, forType: .string)
    }
}

// Tree view for JSON
struct JSONTreeView: View {
    let jsonObject: Any
    let level: Int
    @State private var isExpanded = true
    
    private let indent: CGFloat = 20
    
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
                ForEach(Array(dict.keys.sorted()), id: \.self) { key in
                    HStack(alignment: .top, spacing: 4) {
                        Text(String(repeating: " ", count: level * 2))
                            .font(.system(.body, design: .monospaced))
                        
                        Text("\"\(key)\":")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.purple)
                        
                        JSONTreeView(jsonObject: dict[key]!, level: level + 1)
                    }
                }
                
                Text(String(repeating: " ", count: level * 2) + "}")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
            } else {
                Text("...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, CGFloat(level * 2) * 8)
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
                ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 4) {
                        Text(String(repeating: " ", count: level * 2))
                            .font(.system(.body, design: .monospaced))
                        
                        Text("[\(index)]:")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.orange)
                        
                        JSONTreeView(jsonObject: item, level: level + 1)
                    }
                }
                
                Text(String(repeating: " ", count: level * 2) + "]")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
            } else {
                Text("...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, CGFloat(level * 2) * 8)
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

