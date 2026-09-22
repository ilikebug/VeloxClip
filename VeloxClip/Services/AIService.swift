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

// Thread-safe cache for embeddings using actor
private actor EmbeddingCache {
    private var cache: FIFOCache<String, [Double]>

    init(maxSize: Int = 200) {
        cache = FIFOCache(maxEntries: maxSize)
    }

    func get(_ key: String) -> [Double]? {
        cache[key]
    }

    func set(_ key: String, value: [Double]) {
        cache[key] = value
    }

    func clear() {
        cache.removeAll()
    }
}

// Owns the NLEmbedding models. They are not documented thread-safe, and the
// per-copy embedding (background task) and the search-as-you-type embedding
// (another detached task) used to call into the same instance concurrently.
private actor EmbeddingEngine {
    // Chinese content needs its own model — the English model returns nil for it.
    private let english = NLEmbedding.sentenceEmbedding(for: .english)
    private let chinese = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)

    func vector(for text: String) -> [Double]? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(200)))
        let model: NLEmbedding?
        if let language = recognizer.dominantLanguage,
           language == .simplifiedChinese || language == .traditionalChinese {
            model = chinese ?? english
        } else {
            model = english
        }
        return model?.vector(for: text)
    }
}

final class AIService: Sendable {
    static let shared = AIService()
    
    private let engine = EmbeddingEngine()

    // Thread-safe embedding cache using actor
    private let embeddingCache = EmbeddingCache(maxSize: 200)
    
    private init() {}
    
    // OCR using Apple Vision
    func performOCR(on imageData: Data, completion: @escaping @Sendable (String?) -> Void) {
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
    
    func generateEmbedding(for text: String) async -> [Double]? {
        let textToEmbed = Self.textToEmbed(for: text)
        guard !textToEmbed.isEmpty else { return nil }

        // Keyed on the FULL text, not the truncated copy. Using the truncation
        // as the key meant two documents sharing an opening collapsed to one
        // entry — the second silently received the first one's vector.
        let key = Self.cacheKey(for: text)
        if let cached = await embeddingCache.get(key) {
            return cached
        }

        // Generate embedding (serialized through the engine actor)
        guard let vector = await engine.vector(for: textToEmbed) else {
            return nil
        }

        await embeddingCache.set(key, value: vector)

        return vector
    }

    /// Upper bound on what is actually handed to the embedding model.
    ///
    /// Must be at least `ClipboardIngestion.maxEmbeddableLength`, or items that
    /// ingestion embedded are only partially represented when searched. The
    /// cap still exists so a pathological paste cannot stall the embedder.
    static let maxEmbeddingLength = ClipboardIngestion.maxEmbeddableLength

    /// The text handed to the model: normalized, and bounded for safety.
    static func textToEmbed(for text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.count > maxEmbeddingLength
            ? String(normalized.prefix(maxEmbeddingLength))
            : normalized
    }

    /// Cache key over the WHOLE normalized text, so documents that differ only
    /// past the truncation point still get their own entry.
    static func cacheKey(for text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ClipboardItem.hash(of: Data(normalized.utf8))
    }
    
    func clearEmbeddingCache() async {
        await embeddingCache.clear()
    }
    
    func calculateSimilarity(_ vector1: [Double], _ vector2: [Double]) -> Double {
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
    
    func convertCase(_ text: String, to caseType: TextCaseType) -> String {
        switch caseType {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        }
    }
    
    func cleanupText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum TextCaseType: Sendable {
    case uppercase, lowercase
}
