import SwiftUI
import AppKit

// Table preview for CSV/TSV data
struct TablePreviewView: View {
    let content: String
    @State private var parsedData: [[String]] = []
    @State private var headers: [String] = []
    @State private var delimiter: String = ","
    @State private var searchText: String = ""
    /// Lowercased joined text per row, built once at parse time. `filteredData`
    /// used to join + locale-search every row on each keystroke, synchronously
    /// on the main thread, against an undebounced field.
    @State private var searchKeys: [String] = []
    @State private var filteredRows: [[String]] = []
    @State private var filterTask: Task<Void, Never>?

    private var delimiterLabel: String {
        TablePreviewPresentation.delimiterLabel(for: delimiter)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toolbar
            HStack {
                Text(TablePreviewPresentation.formatLabel)
                    .font(.dsCaption)
                    .foregroundColor(.secondary)
                
                Menu {
                    Button(TablePreviewPresentation.delimiterLabel(for: ",")) { delimiter = "," }
                    Button(TablePreviewPresentation.delimiterLabel(for: "\t")) { delimiter = "\t" }
                    Button(TablePreviewPresentation.delimiterLabel(for: "|")) { delimiter = "|" }
                } label: {
                    HStack(spacing: 4) {
                        Text(delimiterLabel).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .compactMenuLabel(width: 120)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .onChange(of: delimiter) { _, _ in
                    Task { await parseDataAsync() }
                }
                
                TextField(TablePreviewPresentation.searchPlaceholder, text: $searchText)
                    .dsTextField(width: 200)
                
                Spacer()
                
                Text(TablePreviewPresentation.rowColumnSummary(rows: parsedData.count, columns: headers.count))
                    .font(.dsCaption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            // Table view
            if !parsedData.isEmpty {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        TableView(rows: filteredData, headers: headers)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
 else {
                Text(TablePreviewPresentation.emptyMessage)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        // Parsing splits the whole document; every sibling preview does this
        // off the main thread in .task(id:) and this one used to do it in
        // .onAppear.
        .task(id: content) {
            parsedData = []
            headers = []
            searchKeys = []
            filteredRows = []
            detectDelimiter()
            await parseDataAsync()
        }
        .task(id: searchText) {
            await applyFilter()
        }
    }

    /// Debounced so a fast typist doesn't re-scan the table per keystroke —
    /// MainView's own search already worked this way; this one did not.
    private func applyFilter() async {
        guard !searchText.isEmpty else {
            filteredRows = parsedData
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        let query = searchText.lowercased()
        let rows = parsedData
        let keys = searchKeys
        filteredRows = await Task.detached(priority: .userInitiated) {
            zip(rows, keys).filter { $0.1.contains(query) }.map(\.0)
        }.value
    }

    private func parseDataAsync() async {
        let source = content
        let sep = delimiter
        let parsed = await Task.detached(priority: .userInitiated) { () -> (headers: [String], rows: [[String]], keys: [String]) in
            let lines = source.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { return ([], [], []) }
            let headers = Self.parseLine(lines[0], delimiter: sep)
            let rows = lines.dropFirst().map { Self.parseLine($0, delimiter: sep) }
            // Precomputed search key per row
            let keys = rows.map { $0.joined(separator: " ").lowercased() }
            return (headers, rows, keys)
        }.value

        headers = parsed.headers
        parsedData = parsed.rows
        searchKeys = parsed.keys
        filteredRows = parsed.rows
    }
    
    private var filteredData: [[String]] { filteredRows }
    
    private func detectDelimiter() {
        let lines = content.components(separatedBy: .newlines).prefix(5)
        guard let firstLine = lines.first else { return }
        
        let commaCount = firstLine.components(separatedBy: ",").count
        let tabCount = firstLine.components(separatedBy: "\t").count
        let pipeCount = firstLine.components(separatedBy: "|").count
        
        if tabCount > commaCount && tabCount > pipeCount {
            delimiter = "\t"
        } else if pipeCount > commaCount && pipeCount > tabCount {
            delimiter = "|"
        } else {
            delimiter = ","
        }
    }
    

    nonisolated static func parseLine(_ line: String, delimiter: String) -> [String] {
        // Simple CSV parsing (doesn't handle quoted fields with commas)
        return line.components(separatedBy: delimiter)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
}

// Table view component
struct TableView: View {
    let rows: [[String]]
    let headers: [String]
    
    // Lazy loading state
    @State private var loadedRows: [(Int, [String])] = []
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var isLoadingMore = false
    
    private let rowsPerPage = 50
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    TableCell(content: header, isHeader: true)
                        .frame(width: 150)
                }
            }
            .background(Color.secondary.opacity(0.1))
            
            Divider()
            
            // Data rows with lazy loading
            VStack(alignment: .leading, spacing: 0) {
                ForEach(loadedRows, id: \.0) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            TableCell(content: cell, isHeader: false)
                                .frame(width: 150)
                        }
                    }
                    
                    if rowIndex < rows.count - 1 {
                        Divider()
                    }
                }
                
                if loadedRows.count < rows.count {
                    loadMoreIndicator
                        .onAppear {
                            loadMoreWithDebounce()
                        }
                }
            }
        }
        .background(Color.secondary.opacity(0.05))
        .onAppear {
            if loadedRows.isEmpty {
                loadInitialRows()
            }
        }
        .onChange(of: rows) { _, _ in
            // Reset state when rows change
            loadedRows = []
            loadMoreTask?.cancel()
            isLoadingMore = false
            loadInitialRows()
        }
    }
    
    private func loadInitialRows() {
        let allRows = rows.enumerated().map { ($0.offset, $0.element) }
        let initialCount = min(rowsPerPage, allRows.count)
        loadedRows = Array(allRows.prefix(initialCount))
    }
    
    private var loadMoreIndicator: some View {
        HStack {
            if isLoadingMore {
                ProgressView()
                    .scaleEffect(0.7)
                Text(TablePreviewPresentation.loadingMoreRowsTitle)
                    .font(.dsCaption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private func loadMoreWithDebounce() {
        guard !isLoadingMore && loadedRows.count < rows.count else { return }
        
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            isLoadingMore = true
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            if !Task.isCancelled {
                await MainActor.run {
                    let allRows = rows.enumerated().map { ($0.offset, $0.element) }
                    let nextCount = min(loadedRows.count + rowsPerPage, allRows.count)
                    loadedRows = Array(allRows.prefix(nextCount))
                    isLoadingMore = false
                }
            } else {
                isLoadingMore = false
            }
        }
    }
}

struct TableCell: View {
    let content: String
    let isHeader: Bool
    
    var body: some View {
        Text(content)
            .font(isHeader ? .dsCaption.bold() : .dsCaption)
            .foregroundColor(isHeader ? .primary : .secondary)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
    }
}
