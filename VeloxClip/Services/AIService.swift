import Foundation
import Vision
import AppKit
import NaturalLanguage

@MainActor
class AIService {
    static let shared = AIService()
    
    // Sentence embedding model for semantic search
    private let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    
    // Embedding cache to avoid recomputing same queries
    private var embeddingCache: [String: [Double]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.veloxclip.embeddingCache", attributes: .concurrent)
    private let maxCacheSize = 100 // Limit cache size
    
    // Error handling
    enum AIServiceError: LocalizedError {
        case embeddingUnavailable
        case embeddingGenerationFailed
        case invalidInput
        
        var errorDescription: String? {
            switch self {
            case .embeddingUnavailable:
                return "Embedding service is not available"
            case .embeddingGenerationFailed:
                return "Failed to generate embedding"
            case .invalidInput:
                return "Invalid input text"
            }
        }
    }
    
    // OCR using Apple Vision
    func performOCR(on imageData: Data, completion: @escaping @Sendable (String?) -> Void) {
        Task.detached(priority: .userInitiated) {
            guard let image = NSImage(data: imageData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                completion(nil)
                return
            }
            
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    completion(nil)
                    return
                }
                
                let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                completion(recognizedText)
            }
            
            request.recognitionLevel = .accurate
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try requestHandler.perform([request])
            } catch {
                print("OCR Error: \(error)")
                completion(nil)
            }
        }
    }
    
    // Generate semantic embedding for text with caching
    func generateEmbedding(for text: String) -> [Double]? {
        guard let embedding = sentenceEmbedding else {
            return nil
        }
        
        // Normalize and validate input
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !normalizedText.isEmpty else {
            return nil
        }
        
        // Limit text length for embedding (very long texts may not embed well)
        let maxLength = 500
        let textToEmbed = normalizedText.count > maxLength 
            ? String(normalizedText.prefix(maxLength)) 
            : normalizedText
        
        // Use textToEmbed as cache key to ensure consistency
        // This ensures that the same truncated text always uses the same cache entry
        let cacheKey = textToEmbed
        
        // Check cache first
        var cachedResult: [Double]?
        cacheQueue.sync {
            cachedResult = embeddingCache[cacheKey]
        }
        
        if let cached = cachedResult {
            return cached
        }
        
        // Generate embedding
        guard let vector = embedding.vector(for: textToEmbed) else {
            return nil
        }
        
        // Cache the result using textToEmbed as key
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Limit cache size by removing oldest entries
            if self.embeddingCache.count >= self.maxCacheSize {
                // Remove 20% of oldest entries (simple FIFO)
                let keysToRemove = Array(self.embeddingCache.keys.prefix(self.maxCacheSize / 5))
                for key in keysToRemove {
                    self.embeddingCache.removeValue(forKey: key)
                }
            }
            
            self.embeddingCache[cacheKey] = vector
        }
        
        return vector
    }
    
    // Clear embedding cache (useful for memory management)
    func clearEmbeddingCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.embeddingCache.removeAll()
        }
    }
    
    func calculateSimilarity(_ vector1: [Double], _ vector2: [Double]) -> Double {
        guard vector1.count == vector2.count else { return 0 }
        let dotProduct = zip(vector1, vector2).map(*).reduce(0, +)
        let magnitude1 = sqrt(vector1.map { $0 * $0 }.reduce(0, +))
        let magnitude2 = sqrt(vector2.map { $0 * $0 }.reduce(0, +))
        return dotProduct / (magnitude1 * magnitude2)
    }
    
    // MARK: - Magic Actions
    
    // Format JSON with proper indentation
    func formatJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return formatted
    }
    
    // Convert text to different cases
    func convertCase(_ text: String, to caseType: TextCaseType) -> String {
        switch caseType {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return text.capitalized
        case .camelCase:
            let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            let filtered = words.filter { !$0.isEmpty }
            guard !filtered.isEmpty else { return text }
            let first = filtered[0].lowercased()
            let rest = filtered.dropFirst().map { $0.capitalized }
            return ([first] + rest).joined()
        case .snakeCase:
            return text.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }
    
    // Remove extra whitespace and clean up text
    func cleanupText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        let nonEmpty = trimmed.filter { !$0.isEmpty }
        return nonEmpty.joined(separator: "\n")
    }
    
    // Extract URLs from text
    func extractURLs(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
    
    // Placeholder for LLM-based actions (to be implemented with llama.cpp)
    func processMagicAction(action: String, content: String) async -> String {
        // Future: Call local LLM for translation, summarization, etc.
        return "Processed: \(content)"
    }
}

enum TextCaseType {
    case uppercase, lowercase, titleCase, camelCase, snakeCase
}
