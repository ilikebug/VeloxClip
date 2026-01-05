import Foundation
import Combine
import NaturalLanguage

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()
    
    // OpenRouter API Configuration
    private let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let modelName = "tngtech/deepseek-r1t2-chimera:free" // Free DeepSeek model
    
    func performAction(_ action: AIAction, content: String) async throws -> String {
        // Check if API key is configured
        let apiKey = AppSettings.shared.openRouterAPIKey
        guard !apiKey.isEmpty else {
            throw LLMError.apiKeyNotConfigured
        }
        
        // Construct prompt based on action
        let responseLanguage = AppSettings.shared.aiResponseLanguage
        let instruction: String
        switch action {
        case .summarize: 
            instruction = generateSummarizeInstruction(for: responseLanguage)
        case .translate: 
            instruction = generateTranslateInstruction(for: responseLanguage)
        case .explainCode: 
            instruction = generateExplainCodeInstruction(for: responseLanguage)
        case .polish: 
            // Detect language and generate appropriate prompt
            let detectedLanguage = detectLanguage(content)
            instruction = generatePolishInstruction(for: detectedLanguage)
        }
        
        // Construct the full prompt
        let fullPrompt = """
\(instruction)

```text
\(content)
```
"""
        
        // Call OpenRouter API
        return try await generateResponseOpenRouter(prompt: fullPrompt, apiKey: apiKey)
    }
    
    // MARK: - OpenRouter API
    
    private func generateResponseOpenRouter(prompt: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: openRouterURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("VeloxClip/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("https://github.com/antigravity/veloxclip", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60 // 60 seconds timeout
        
        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.7,
            "max_tokens": 2048
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        // Handle HTTP errors
        if httpResponse.statusCode != 200 {
            if httpResponse.statusCode == 401 {
                throw LLMError.invalidAPIKey
            } else if httpResponse.statusCode == 429 {
                throw LLMError.rateLimitExceeded
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
        }
        
        // Parse response
        struct OpenRouterResponse: Decodable {
            let choices: [Choice]
            
            struct Choice: Decodable {
                let message: Message
                
                struct Message: Decodable {
                    let content: String
                }
            }
        }
        
        do {
            let result = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            guard let firstChoice = result.choices.first else {
                throw LLMError.invalidResponse
            }
            
            var output = firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Clean up output - remove markdown code fences if present
            if output.hasPrefix("```") {
                let lines = output.components(separatedBy: .newlines)
                            var cleanedLines: [String] = []
                var skipCodeFence = true
                
                for line in lines {
                    if skipCodeFence && line.hasPrefix("```") {
                        skipCodeFence = false
                                    continue
                                }
                    if !skipCodeFence {
                        cleanedLines.append(line)
                    }
                }
                
                // Remove trailing code fence if present
                if let lastLine = cleanedLines.last, lastLine.hasPrefix("```") {
                    cleanedLines.removeLast()
                }
                
                output = cleanedLines.joined(separator: "\n")
            }
            
            return output.isEmpty ? "[Empty response]" : output
        } catch {
            print("Failed to decode OpenRouter response: \(error)")
            throw LLMError.decodingError
        }
    }
    
    // MARK: - Language Detection
    
    private func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        if let dominantLanguage = recognizer.dominantLanguage {
            let langCode = dominantLanguage.rawValue
            
            // Map language codes to readable names
            switch langCode {
            case "en": return "English"
            case "zh-Hans", "zh-Hant": return "Chinese"
            case "ja": return "Japanese"
            case "ko": return "Korean"
            case "es": return "Spanish"
            case "fr": return "French"
            case "de": return "German"
            case "it": return "Italian"
            case "pt": return "Portuguese"
            case "ru": return "Russian"
            default: return "English"
            }
        }
        
        return "English"
    }
    
    // MARK: - Instruction Generation
    
    private func generateSummarizeInstruction(for language: String) -> String {
        switch language {
        case "Chinese":
            return """
请用中文简要总结以下文本。

重要要求：
1. 只输出总结内容，不要输出"总结："、"摘要："等前缀
2. 不要重复输出相同的内容
3. 直接输出总结结果，不要添加格式标记
"""
        case "English":
            return """
Please briefly summarize the following text in English.

Important requirements:
1. Only output the summary content, do not output prefixes like "Summary:" or "Abstract:"
2. Do not repeat the same content
3. Output the summary result directly without format markers
"""
        case "Japanese":
            return """
以下のテキストを日本語で簡潔に要約してください。

重要な要件：
1. 要約内容のみを出力し、「要約：」や「概要：」などの接頭辞を出力しないでください
2. 同じ内容を繰り返さないでください
3. フォーマットマーカーなしで要約結果を直接出力してください
"""
        case "Korean":
            return """
다음 텍스트를 한국어로 간단히 요약해 주세요.

중요한 요구사항:
1. 요약 내용만 출력하고 "요약:" 또는 "개요:"와 같은 접두사를 출력하지 마세요
2. 동일한 내용을 반복하지 마세요
3. 형식 마커 없이 요약 결과를 직접 출력하세요
"""
        default:
            return """
Please briefly summarize the following text in \(language).

Important requirements:
1. Only output the summary content, do not output prefixes
2. Do not repeat the same content
3. Output the summary result directly without format markers
"""
        }
    }
    
    private func generateTranslateInstruction(for language: String) -> String {
        switch language {
        case "Chinese":
            return """
请将以下内容翻译成中文。

【重要】只输出翻译结果，不要输出本指令的任何内容。

如果是单词，严格按照以下格式输出（每个字段都必须包含）：
发音: /音标/
n. 名词释义（多个义项用分号分隔）
v. 动词释义（多个义项用分号分隔）
（如有其他词性如adj./adv./prep.等，按同样格式列出）
时态:
第三人称单数: xxx
现在分词: xxx
过去式: xxx
过去分词: xxx
解释: 详细的中文解释
词源学: 词源信息（不知道写"无"）
记忆方法: 记忆方法（不知道写"无"）
同根词: 同根词列表（没有写"None"）
近义词: 近义词列表（用逗号分隔，没有写"None"）
反义词: 反义词列表（用逗号分隔，没有写"None"）
常用短语: 常用短语及其中文翻译（用分号分隔，没有写"None"）
例句:
英文例句1 中文翻译1 *（标注使用的义项）*
英文例句2 中文翻译2 *（标注使用的义项）*
（至少提供2-3个例句）

如果是句子或段落，直接输出中文翻译，不要添加任何前缀、后缀或说明文字。

现在开始翻译，只输出翻译结果：
"""
        case "English":
            return """
Please translate the following content to English.

Strict format requirements (must be strictly followed, output format must be completely consistent every time):
1. Only output the translated English content, do not output the original content
2. Absolutely do not output prefixes or suffixes like "Translation:", "English:", "Translated:", etc.
3. If it's a word, you must strictly follow this template format (every field must be included):
   **word** [phonetic]
   - **Part of speech**: ...
   - **Definition**: ...
   - **Example**: ... (if available, omit if not)
4. If it's a sentence or paragraph, output the English translation directly without any format markers, prefixes, suffixes, or explanatory text
5. Do not repeat the same content
6. Output format must be consistent, the format must be exactly the same every time when translating the same content

Please strictly follow the above format requirements and ensure the output format is completely consistent every time.
"""
        case "Japanese":
            return """
以下の内容を日本語に翻訳してください。

厳格な形式要件（厳密に遵守する必要があり、出力形式は毎回完全に一致する必要があります）：
1. 翻訳された日本語の内容のみを出力し、元の内容を出力しないでください
2. 「日本語翻訳：」、「翻訳：」、「Translation:」、「訳文：」などの接頭辞や接尾辞を絶対に出力しないでください
3. 単語の場合は、以下のテンプレート形式を厳密に遵守してください（各フィールドを含める必要があります）：
   **単語** [音声記号]
   - **品詞**: ...
   - **意味**: ...
   - **例文**: ...（ある場合は、ない場合は省略）
4. 文や段落の場合は、フォーマットマーカー、接頭辞、接尾辞、説明文なしで日本語翻訳を直接出力してください
5. 同じ内容を繰り返さないでください
6. 出力形式は一貫している必要があり、同じ内容を翻訳する際は毎回形式が完全に同じである必要があります

上記の形式要件を厳密に遵守し、出力形式が毎回完全に一致することを確認してください。
"""
        case "Korean":
            return """
다음 내용을 한국어로 번역해 주세요.

엄격한 형식 요구사항(엄격히 준수해야 하며, 출력 형식은 매번 완전히 일치해야 함):
1. 번역된 한국어 내용만 출력하고 원본 내용을 출력하지 마세요
2. "한국어 번역:", "번역:", "Translation:", "번역문:"과 같은 접두사나 접미사를 절대 출력하지 마세요
3. 단어인 경우 다음 템플릿 형식을 엄격히 준수해야 합니다(모든 필드를 포함해야 함):
   **단어** [음성 기호]
   - **품사**: ...
   - **의미**: ...
   - **예문**: ... (있는 경우, 없는 경우 생략)
4. 문장이나 단락인 경우 형식 마커, 접두사, 접미사, 설명 텍스트 없이 한국어 번역을 직접 출력하세요
5. 동일한 내용을 반복하지 마세요
6. 출력 형식은 일관되어야 하며, 동일한 내용을 번역할 때마다 형식이 완전히 동일해야 합니다

위 형식 요구사항을 엄격히 준수하고 출력 형식이 매번 완전히 일치하는지 확인하세요.
"""
        default:
            return """
Please translate the following content to \(language).

Strict format requirements (must be strictly followed, output format must be completely consistent every time):
1. Only output the translated content, do not output the original content
2. Absolutely do not output prefixes or suffixes
3. Output the translation directly without any format markers, prefixes, suffixes, or explanatory text
4. Do not repeat the same content
5. Output format must be consistent, the format must be exactly the same every time when translating the same content

Please strictly follow the above format requirements and ensure the output format is completely consistent every time.
"""
        }
    }
    
    private func generateExplainCodeInstruction(for language: String) -> String {
        switch language {
        case "Chinese":
            return """
请用中文解释这段代码的功能。

重要要求：
1. 只输出解释内容，不要输出"解释："、"说明："等前缀
2. 不要重复输出相同的内容
3. 直接输出解释结果，不要添加格式标记
"""
        case "English":
            return """
Please explain what this code does in English.

Important requirements:
1. Only output the explanation content, do not output prefixes like "Explanation:" or "Description:"
2. Do not repeat the same content
3. Output the explanation result directly without format markers
"""
        case "Japanese":
            return """
このコードの機能を日本語で説明してください。

重要な要件：
1. 説明内容のみを出力し、「説明：」や「解説：」などの接頭辞を出力しないでください
2. 同じ内容を繰り返さないでください
3. フォーマットマーカーなしで説明結果を直接出力してください
"""
        case "Korean":
            return """
이 코드의 기능을 한국어로 설명해 주세요.

중요한 요구사항:
1. 설명 내용만 출력하고 "설명:" 또는 "해설:"과 같은 접두사를 출력하지 마세요
2. 동일한 내용을 반복하지 마세요
3. 형식 마커 없이 설명 결과를 직접 출력하세요
"""
        default:
            return """
Please explain what this code does in \(language).

Important requirements:
1. Only output the explanation content, do not output prefixes
2. Do not repeat the same content
3. Output the explanation result directly without format markers
"""
        }
    }
    
    private func generatePolishInstruction(for language: String) -> String {
        switch language {
        case "Chinese":
            return """
请润色以下中文文本，使其更通顺专业。

重要要求：
1. 保持中文语言，不要翻译成其他语言
2. 只输出润色后的内容，不要输出"润色："、"修改后："等前缀
3. 不要重复输出相同的内容
4. 直接输出润色结果，不要添加格式标记
"""
        case "English":
            return """
Please polish the following English text to make it more fluent and professional.

Important requirements:
1. Keep the text in English, do not translate to other languages
2. Only output the polished content, do not output prefixes like "Polished:" or "Revised:"
3. Do not repeat the same content
4. Output the polished result directly without format markers
"""
        case "Japanese":
            return """
以下の日本語テキストをより流暢で専門的に磨き上げてください。

重要な要件：
1. 日本語を保持し、他の言語に翻訳しないでください
2. 磨き上げた内容のみを出力し、「磨き上げ：」や「修正後：」などの接頭辞を出力しないでください
3. 同じ内容を繰り返さないでください
4. フォーマットマーカーなしで磨き上げた結果を直接出力してください
"""
        case "Korean":
            return """
다음 한국어 텍스트를 더 유창하고 전문적으로 다듬어 주세요.

중요한 요구사항:
1. 한국어를 유지하고 다른 언어로 번역하지 마세요
2. 다듬은 내용만 출력하고 "다듬기:" 또는 "수정 후:"와 같은 접두사를 출력하지 마세요
3. 동일한 내용을 반복하지 마세요
4. 형식 마커 없이 다듬은 결과를 직접 출력하세요
"""
        default:
            return """
Please polish the following text to make it more fluent and professional. Keep the text in its original language (\(language)).

Important requirements:
1. Keep the text in \(language), do not translate to other languages
2. Only output the polished content, do not output prefixes like "Polished:" or "Revised:"
3. Do not repeat the same content
4. Output the polished result directly without format markers
"""
        }
    }
}

enum AIAction: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case translate = "Translate"
    case explainCode = "Explain Code"
    case polish = "Polish"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .summarize: return "text.alignleft"
        case .translate: return "character.book.closed"
        case .explainCode: return "hammer"
        case .polish: return "wand.and.stars"
        }
    }
}

enum LLMError: LocalizedError {
    case apiKeyNotConfigured
    case invalidAPIKey
    case invalidResponse
    case decodingError
    case rateLimitExceeded
    case apiError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "OpenRouter API Key is not configured. Please set it in Settings."
        case .invalidAPIKey:
            return "Invalid OpenRouter API Key. Please check your API key in Settings."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .decodingError:
            return "Failed to decode AI response."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .apiError(let statusCode, let message):
            return "API error (status \(statusCode)): \(message)"
        }
    }
}
