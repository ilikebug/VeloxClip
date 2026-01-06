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
            .padding(.bottom, 8)
            
            // Table view
            if !parsedData.isEmpty {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    TableView(rows: filteredData, headers: headers)
                }
                .frame(maxHeight: 400)
            } else {
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
            
            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
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
        }
        .background(Color(white: 0.95))
        .cornerRadius(8)
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

