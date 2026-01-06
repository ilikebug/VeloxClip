import SwiftUI
import AppKit

// Table preview for CSV/TSV data
struct TablePreviewView: View {
    let content: String
    @State private var parsedData: [[String]] = []
    @State private var headers: [String] = []
    @State private var delimiter: String = ","
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toolbar
            HStack {
                Text("Format:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $delimiter) {
                    Text("CSV (,)").tag(",")
                    Text("TSV (Tab)").tag("\t")
                    Text("Pipe (|)").tag("|")
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .onChange(of: delimiter) { oldValue, newValue in
                    parseData()
                }
                
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                
                Spacer()
                
                Text("\(parsedData.count) rows, \(headers.count) columns")
                    .font(.caption)
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
                .background(Color.white)
            }
 else {
                Text("No table data found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .onAppear {
            detectDelimiter()
            parseData()
        }
        .onChange(of: content) { _, _ in
            // Reset and reparse when content changes
            parsedData = []
            headers = []
            detectDelimiter()
            parseData()
        }
    }
    
    private var filteredData: [[String]] {
        if searchText.isEmpty {
            return parsedData
        }
        
        return parsedData.filter { row in
            row.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        }
    }
    
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
    
    private func parseData() {
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        guard !lines.isEmpty else {
            parsedData = []
            headers = []
            return
        }
        
        // First line as headers
        headers = parseLine(lines[0])
        
        // Rest as data
        parsedData = lines.dropFirst().map { parseLine($0) }
    }
    
    private func parseLine(_ line: String) -> [String] {
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
            .background(Color(white: 0.9))
            
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
        .background(Color(white: 0.98))
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
                Text("Loading more rows...")
                    .font(.caption)
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
            .font(isHeader ? .caption.bold() : .caption)
            .foregroundColor(isHeader ? .primary : .secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
    }
}

