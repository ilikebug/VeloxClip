import Foundation

struct ClipboardItem: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var createdAt: Date
    var type: String
    var content: String?
    var data: Data?
    var sourceApp: String?
    
    // AI Metadata
    var tags: [String] = []
    var summary: String?
    var isSensitive: Bool = false
    var embedding: Data?
    
    // Favorite Metadata
    var isFavorite: Bool = false
    var favoritedAt: Date?
    
    var vector: [Double]? {
        guard let data = embedding else { return nil }
        return try? JSONDecoder().decode([Double].self, from: data)
    }
    
    init(type: String, content: String? = nil, data: Data? = nil, sourceApp: String? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.type = type
        self.content = content
        self.data = data
        self.sourceApp = sourceApp
    }
}

import AppKit

extension ClipboardItem {
    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if type == "image", let d = data, let nsImage = NSImage(data: d) {
            // Convert to TIFF format
            if let tiffData = nsImage.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
            
            // Convert to PNG format
            if let tiffData = nsImage.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }
            
            // Also set as NSImage for better compatibility
            pasteboard.writeObjects([nsImage])
            return
        }
        
        if type == "color", let c = content {
            pasteboard.setString(c, forType: .string)
            return
        }
        
        if let c = content {
            pasteboard.setString(c, forType: .string)
        } else if let d = data {
            if type == "rtf" {
                pasteboard.setData(d, forType: .rtf)
            }
        }
    }
}
