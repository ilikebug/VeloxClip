import Foundation
import Vision
import AppKit
import NaturalLanguage
import Accelerate

enum AIServiceError: LocalizedError, Sendable {
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

actor AIService {
    static let shared = AIService()
    
    // Sentence embedding model for semantic search
    private let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    
    // Embedding cache
    private var embeddingCache: [String: [Double]] = [:]
    private let maxCacheSize = 200
    
    // OCR using Apple Vision
    nonisolated func performOCR(on imageData: Data, completion: @escaping @Sendable (String?) -> Void) {
        Task.detached(priority: .userInitiated) {
            guard let image = NSImage(data: imageData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                completion(nil)
                return
            }
            
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("OCR Error: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    completion(nil)
                    return
                }
                
                let recognizedText = observations.compactMap { observation -> String? in
                    let candidates = observation.topCandidates(3)
                    guard let bestCandidate = candidates.first else { return nil }
                    
                    if bestCandidate.confidence > 0.9 { return bestCandidate.string }
                    
                    var bestText = bestCandidate.string
                    var bestScore = bestCandidate.confidence
                    let chinesePunctuation = "，。！？；：、\u{201C}\u{201D}\u{2018}\u{2019}（）【】《》"
                    let englishPunctuation = ".,!?;:\"'-()[]{}"
                    
                    for candidate in candidates.dropFirst() {
                        if candidate.confidence > bestScore - 0.1 {
                            let candidateText = candidate.string
                            let candidatePunctCount = candidateText.filter { chinesePunctuation.contains($0) || englishPunctuation.contains($0) }.count
                            let bestPunctCount = bestText.filter { chinesePunctuation.contains($0) || englishPunctuation.contains($0) }.count
                            if candidatePunctCount > bestPunctCount && candidate.confidence > 0.7 {
                                bestText = candidateText
                                bestScore = candidate.confidence
                            }
                        }
                    }
                    return bestText
                }.joined(separator: "\n")
                
                completion(recognizedText.isEmpty ? nil : recognizedText)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try requestHandler.perform([request])
            } catch {
                print("OCR Error: \(error)")
                completion(nil)
            }
        }
    }
    
    func generateEmbedding(for text: String) -> [Double]? {
        guard let embedding = sentenceEmbedding else { return nil }
        
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedText.isEmpty else { return nil }
        
        let maxLength = 500
        let textToEmbed = normalizedText.count > maxLength 
            ? String(normalizedText.prefix(maxLength)) 
            : normalizedText
        
        if let cached = embeddingCache[textToEmbed] {
            return cached
        }
        
        guard let vector = embedding.vector(for: textToEmbed) else { return nil }
        
        if embeddingCache.count >= maxCacheSize {
            embeddingCache.removeValue(forKey: embeddingCache.keys.first!)
        }
        embeddingCache[textToEmbed] = vector
        
        return vector
    }
    
    func clearEmbeddingCache() {
        embeddingCache.removeAll()
    }
    
    nonisolated func calculateSimilarity(_ vector1: [Double], _ vector2: [Double]) -> Double {
        let n = vDSP_Length(vector1.count)
        guard n > 0 && vector1.count == vector2.count else { return 0 }
        
        var dotProduct: Double = 0
        vDSP_dotprD(vector1, 1, vector2, 1, &dotProduct, n)
        
        var squaredSum1: Double = 0
        vDSP_svesqD(vector1, 1, &squaredSum1, n)
        
        var squaredSum2: Double = 0
        vDSP_svesqD(vector2, 1, &squaredSum2, n)
        
        let magnitude1 = sqrt(squaredSum1)
        let magnitude2 = sqrt(squaredSum2)
        
        let denominator = magnitude1 * magnitude2
        return denominator == 0 ? 0 : dotProduct / denominator
    }
    
    nonisolated func formatJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return formatted
    }
    
    nonisolated func convertCase(_ text: String, to caseType: TextCaseType) -> String {
        switch caseType {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titleCase: return text.capitalized
        case .camelCase:
            let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            guard !words.isEmpty else { return text }
            return ([words[0].lowercased()] + words.dropFirst().map { $0.capitalized }).joined()
        case .snakeCase: return text.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }
    
    nonisolated func cleanupText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum TextCaseType: Sendable {
    case uppercase, lowercase, titleCase, camelCase, snakeCase
}
