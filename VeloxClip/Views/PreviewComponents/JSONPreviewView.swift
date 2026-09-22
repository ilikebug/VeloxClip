import SwiftUI
import AppKit

// JSON preview with formatting and validation
struct JSONPreviewView: View {
    @Environment(\.colorScheme) private var scheme
    let jsonString: String
    @ObservedObject private var settings = AppSettings.shared
    @State private var formattedJSON: String = ""
    @State private var minifiedJSONText: String = ""
    @State private var isValidJSON = false
    @State private var validationError: String?
    @State private var viewMode: ViewMode = .formatted
    // Parsed once per item for tree mode — re-parsing inside body ran on every
    // layout pass and store publish (multi-second hangs on large documents)
    @State private var jsonObject: Any?
    /// Split once per document. Splitting inside `body` re-allocated the whole
    /// line array on every body evaluation (scheme change, settings publish,
    /// viewMode toggle), not just when the document changed.
    @State private var formattedLines: [String] = []
    
    enum ViewMode {
        case formatted, minified, tree

        func segmentLabel(language: AppLanguage) -> String {
            switch self {
            case .formatted: return L10n.string("preview.json.formatted", language: language)
            case .minified: return L10n.string("preview.json.minified", language: language)
            case .tree: return L10n.string("preview.json.tree", language: language)
            }
        }
    }
    
    @State private var isLoading = true
    
    // Static cache for processed JSON to persist across view updates.
    // Cleared via CacheRegistry (see ViewCaches.registerAll).
    @MainActor
    static var jsonCache = FIFOCache<String, (formatted: String, minified: String, isValid: Bool, error: String?)>(maxEntries: 100)
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                header.padding(.horizontal, 16)
                contentArea(availableWidth: geo.size.width)
            }
        }
        .task(id: jsonString) {
            jsonObject = nil
            formattedLines = []
            await validateAndFormatAsync()
        }
    }
    
    private var header: some View {
        HStack(spacing: 10) {
            validationStatus
            
            Spacer()
            
            if !isLoading {
                HStack(spacing: 4) {
                    ForEach([ViewMode.formatted, .minified, .tree], id: \.self) { mode in
                        Button(mode.segmentLabel(language: settings.appLanguage)) { viewMode = mode }
                            .dsButton(viewMode == mode ? .prominent : .secondary, small: true)
                    }
                }

                Button(action: copyJSON) {
                    Label(L10n.string("command.copy", language: settings.appLanguage), systemImage: "doc.on.doc")
                }
                .dsButton(small: true)
            }
        }
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var validationStatus: some View {
        let c = DSColors(scheme: scheme)
        if isLoading {
            ProgressView().scaleEffect(0.7)
            Text(L10n.string("preview.json.validating", language: settings.appLanguage)).font(.system(size: 11)).foregroundColor(c.text2)
        } else if isValidJSON {
            Label(L10n.string("preview.json.valid", language: settings.appLanguage), systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(.green)
        } else if let error = validationError {
            Label(L10n.string("preview.json.invalid", language: settings.appLanguage), systemImage: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(.red).help(error)
        }
    }

    private func contentArea(availableWidth: CGFloat) -> some View {
        let c = DSColors(scheme: scheme)
        return ScrollView([.horizontal, .vertical], showsIndicators: true) {
            Group {
                if isLoading {
                    loadingSpinner
                } else if isValidJSON {
                    switch viewMode {
                    case .formatted:
                        formattedView(availableWidth: availableWidth)
                    case .minified:
                        minifiedView(availableWidth: availableWidth)
                    case .tree:
                        treeView(availableWidth: availableWidth)
                    }
                } else {
                    errorView
                        .frame(width: availableWidth, alignment: .leading)
                }
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(c.card))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .scrollIndicators(.visible)
    }

    private var loadingSpinner: some View {
        let c = DSColors(scheme: scheme)
        return VStack(spacing: 8) {
            ProgressView()
            Text(L10n.string("preview.json.loading", language: settings.appLanguage)).font(.system(size: 11)).foregroundColor(c.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func formattedView(availableWidth: CGFloat) -> some View {
        let c = DSColors(scheme: scheme)
        // Lazy: a pretty-printed multi-MB document has hundreds of thousands of
        // lines; instantiating a Text for each up front froze the overlay
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(formattedLines.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .font(.dsMonoBody)
                    .foregroundColor(c.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 40)
                    .padding(.vertical, 1)
            }
        }
        .padding(12)
        .frame(minWidth: availableWidth, alignment: .topLeading)
    }

    private func minifiedView(availableWidth: CGFloat) -> some View {
        let c = DSColors(scheme: scheme)
        return Text(minifiedJSONText)
            .font(.dsMonoBody)
            .foregroundColor(c.text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .textSelection(.enabled)
            .padding(12)
            .padding(.trailing, 40)
            .frame(minWidth: availableWidth, alignment: .topLeading)
    }

    private func treeView(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let jsonObject {
                JSONTreeView(jsonObject: jsonObject, level: 0, language: settings.appLanguage)
            }
        }
        .padding(12)
        .padding(.trailing, 40)
        .frame(minWidth: availableWidth, alignment: .topLeading)
    }

    private var errorView: some View {
        let c = DSColors(scheme: scheme)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("preview.json.error", language: settings.appLanguage)).font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
            if let error = validationError {
                Text(error).font(.dsMonoBody).foregroundColor(c.text2)
            }
            Divider()
            Text(L10n.string("preview.json.raw", language: settings.appLanguage)).font(.system(size: 11)).foregroundColor(c.text2)
            Text(jsonString).font(.dsMonoBody).foregroundColor(c.text).textSelection(.enabled)
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
            // The cache holds strings only; re-derive the line split off the
            // main thread rather than inside body.
            if cached.isValid {
                let formatted = cached.formatted
                self.formattedLines = await Task.detached(priority: .userInitiated) {
                    formatted.components(separatedBy: .newlines)
                }.value
                // JSONSerialization returns `Any`, which can't cross an actor
                // boundary; parse here rather than in body.
                self.jsonObject = input.data(using: .utf8)
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) }
            }
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
                
                let lines = formatted.components(separatedBy: .newlines)

                await MainActor.run {
                    Self.jsonCache[input] = (formatted, minified, true, nil)

                    self.formattedJSON = formatted
                    self.formattedLines = lines
                    self.minifiedJSONText = minified
                    // Reuse the object this pass already produced — it used to
                    // be discarded and re-parsed on the main thread for tree mode
                    self.jsonObject = jsonObject
                    self.isValidJSON = true
                    self.validationError = nil
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    Self.jsonCache[input] = ("", "", false, error.localizedDescription)
                    
                    self.isValidJSON = false
                    self.validationError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }.value
    }
    
    private func copyJSON() {
        let text = viewMode == .minified ? minifiedJSONText : formattedJSON
        PasteboardService.shared.write(text: text)
    }
}


// Tree view for JSON - Postman Style
struct JSONTreeView: View {
    @Environment(\.colorScheme) private var scheme
    let jsonObject: Any
    let level: Int
    let key: String?
    /// Passed down the recursion as a value. This view recurses once per JSON
    /// node, so observing AppSettings installed one observer per node — a
    /// 5000-node document meant 5000 observers all invalidated together.
    let language: AppLanguage
    @State private var isExpanded = true

    private let indent: CGFloat = 20

    // Postman-like colors (content-semantic — preserved)
    private let keyColor = Color(hex: "#A626A4")!     // Purple
    private let stringColor = Color(hex: "#50A14F")!  // Green
    private let numberColor = Color(hex: "#986801")!  // Orange/Brown
    private let keywordColor = Color(hex: "#0184BC")! // Blue

    init(jsonObject: Any, level: Int = 0, key: String? = nil, language: AppLanguage) {
        self.jsonObject = jsonObject
        self.level = level
        self.key = key
        self.language = language
    }

    private var bracketColor: Color { DSColors(scheme: scheme).text2 }

    var body: some View {
        let c = DSColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 2) {
            if let dict = jsonObject as? [String: Any] {
                collectionHeader(label: "{", count: dict.count, type: L10n.string("preview.json.keys", language: language))
                if isExpanded {
                    dictionaryContent(dict)
                    Text("}").foregroundColor(bracketColor).font(.dsMonoBody)
                }
            } else if let array = jsonObject as? [Any] {
                collectionHeader(label: "[", count: array.count, type: L10n.string("preview.json.items", language: language))
                if isExpanded {
                    arrayContent(array)
                    Text("]").foregroundColor(bracketColor).font(.dsMonoBody)
                }
            } else {
                leafValue
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.leading, level == 0 ? 0 : indent)
        // Add a vertical guide line for nested items
        .overlay(
            Group {
                if level > 0 && isExpanded {
                    Rectangle()
                        .fill(c.divider)
                        .frame(width: 1)
                        .padding(.leading, 4)
                        .padding(.vertical, 4)
                }
            },
            alignment: .leading
        )
    }
    
    @ViewBuilder
    private var leafValue: some View {
        HStack(alignment: .top, spacing: 4) {
            if let key = key {
                Text("\"\(key)\":").foregroundColor(keyColor).fontWeight(.medium)
            }
            valueView(jsonObject)
        }
        .font(.dsMonoBody)
    }

    private func collectionHeader(label: String, count: Int, type: String) -> some View {
        let c = DSColors(scheme: scheme)
        return HStack(spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(c.text2)
                    .rotationEffect(isExpanded ? .zero : .degrees(-90))
            }
            .buttonStyle(.plain)
            .frame(width: 12)

            if let key = key {
                Text("\"\(key)\":").foregroundColor(keyColor).fontWeight(.medium)
            }

            Text(label).foregroundColor(bracketColor)

            if !isExpanded {
                Text("… \(count) \(type) …").font(.system(size: 11)).foregroundColor(c.text2)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(c.chip))
                Text(label == "{" ? "}" : "]").foregroundColor(bracketColor)
            }
        }
        .font(.dsMonoBody)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func dictionaryContent(_ dict: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let sortedKeys = dict.keys.sorted()
            ForEach(sortedKeys, id: \.self) { key in
                JSONTreeView(jsonObject: dict[key]!, level: level + 1, key: key, language: language)
            }
        }
    }

    private func arrayContent(_ array: [Any]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                JSONTreeView(jsonObject: item, level: level + 1, language: language)
            }
        }
    }

    private func valueView(_ value: Any) -> some View {
        // Classification lives in JSONValueRendering: NSNumber must be tested
        // before Bool, because JSONSerialization returns every number as an
        // NSNumber and `NSNumber(1) as? Bool` succeeds — which rendered the
        // integers 1 and 0 as `true` and `false`.
        switch JSONValueRendering.describe(value) {
        case .string(let s):
            return Text("\"\(s)\"").foregroundColor(stringColor)
        case .boolean(let b):
            return Text(b).foregroundColor(keywordColor)
        case .null:
            return Text("null").foregroundColor(keywordColor)
        case .number(let n):
            return Text(n).foregroundColor(numberColor)
        case .dictionary, .array, .unknown:
            return Text(String(describing: value)).foregroundColor(DSColors(scheme: scheme).text)
        }
    }
}
