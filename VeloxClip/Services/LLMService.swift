import Foundation
import Combine
import NaturalLanguage

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()
    
    // Configuration
    var modelName: String = "llama3.2" 
    private let ollamaURL = URL(string: "http://127.0.0.1:11434/api/generate")!
    
    // Embedded Configuration
    // Users should place 'llama-cli' and 'model.gguf' in:
    // ~/Library/Application Support/Velox/LLM/
    private let appSupportObj = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Velox/LLM")
    
    // Check mode
    func isOllamaAvailable() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    func performAction(_ action: AIAction, content: String) async throws -> String {
        // 1. Try Ollama first (if running)
        // For now, FORCE EMBEDDED MODE for testing
        /*
        if await isOllamaAvailable() {
            let prompt = constructPrompt(for: action, content: content)
            print("Using Ollama...")
            return try await generateResponseOllama(prompt: prompt)
        }
        */
        
        // 2. Fallback to Embedded/Local Binary
        print("Ollama not found, trying embedded model...")
        return try await generateResponseEmbedded(action: action, content: content)
    }
    
    // MARK: - Embedded Inference
    
    /// Find the first .gguf model file in the specified directory
    private func findModelFile(in directoryPath: String) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryPath) else {
            return nil
        }
        
        // Look for .gguf files
        for file in contents {
            if file.hasSuffix(".gguf") {
                let fullPath = (directoryPath as NSString).appendingPathComponent(file)
                if fileManager.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        
        return nil
    }
    
    private func generateResponseEmbedded(action: AIAction, content: String) async throws -> String {
        // Look in Bundle Resources first (Shipped with App)
        var cliPath = Bundle.main.path(forResource: "llama-cli", ofType: nil)
        var modelPath: String?
        
        // Search for .gguf model files in Bundle Resources
        if let resourcePath = Bundle.main.resourcePath {
            modelPath = findModelFile(in: resourcePath)
        }
        
        // Fallback to Application Support
        if cliPath == nil || modelPath == nil {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Velox/LLM")
            if cliPath == nil { 
                cliPath = appSupport.appendingPathComponent("llama-cli").path 
            }
            if modelPath == nil {
                modelPath = findModelFile(in: appSupport.path)
            }
        }
        
        guard let finalCliPath = cliPath, FileManager.default.fileExists(atPath: finalCliPath) else {
            throw LLMError.binaryNotFound(path: cliPath ?? "Bundle & AppSupport")
        }
        guard let finalModelPath = modelPath, FileManager.default.fileExists(atPath: finalModelPath) else {
            throw LLMError.modelNotFound(path: modelPath ?? "Bundle & AppSupport")
        }
        
        // Construct Instruction Map
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
        
        // Construct prompt - Robust Text-Based Format with Markdown fencing
        let formattedPrompt = """
### User:
\(instruction)

```text
\(content)
```

### Assistant:
"""
        
        // Write prompt to temp file
        let tempPromptURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try formattedPrompt.write(to: tempPromptURL, atomically: true, encoding: .utf8)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var cleanupAttempted = false
                
                // Cleanup function to ensure temp file is removed
                let cleanupTempFile = {
                    if !cleanupAttempted {
                        cleanupAttempted = true
                        do {
                            if FileManager.default.fileExists(atPath: tempPromptURL.path) {
                                try FileManager.default.removeItem(at: tempPromptURL)
                                print("✅ Cleaned up temp file: \(tempPromptURL.lastPathComponent)")
                            }
                        } catch {
                            print("⚠️ Failed to clean up temp file \(tempPromptURL.lastPathComponent): \(error)")
                            // Try again after a short delay in case file is still in use
                            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                                do {
                                    if FileManager.default.fileExists(atPath: tempPromptURL.path) {
                                        try FileManager.default.removeItem(at: tempPromptURL)
                                        print("✅ Cleaned up temp file on retry: \(tempPromptURL.lastPathComponent)")
                                    }
                                } catch {
                                    print("❌ Failed to clean up temp file on retry: \(error)")
                                }
                            }
                        }
                    }
                }
                
                defer {
                    cleanupTempFile()
                }
                
                // Ensure binary is executable
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["+x", finalCliPath]
                try? chmod.run()
                chmod.waitUntilExit()
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: finalCliPath)
                
                process.arguments = [
                    "-m", finalModelPath,
                    "-f", tempPromptURL.path,
                    "-n", "512",
                    "--temp", "0.6",      // Slightly lower temp for precision
                    "--top_k", "40",
                    "--repeat-penalty", "1.2", // Stronger penalty
                    "--no-display-prompt",
                    "-r", "### User:"     // Stop if it hallucinates user
                ]
                
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                
                
                do {
                    print("🚀 Launching llama-cli...")
                    // ... (debug prints)
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    let errOutput = String(data: errData, encoding: .utf8) ?? ""
                    
                    print("📋 stdout:\n\(output)")
                    print("📋 stderr:\n\(errOutput)")
                    
                    if process.terminationStatus == 0 {
                        // Clean up output: remove [end of text] and leading/trailing whitespace
                        var cleanOutput = output.replacingOccurrences(of: "[end of text]", with: "")
                        
                        // Aggressively remove all prompt-related content
                        // Remove system prompts (### User:, ### Assistant:, etc.)
                        let promptMarkers = [
                            "### User:",
                            "### Assistant:",
                            "###User:",
                            "###Assistant:",
                            "User:",
                            "Assistant:",
                            "用户：",
                            "助手：",
                            "用户:",
                            "助手:"
                        ]
                        
                        for marker in promptMarkers {
                            // Remove everything before the marker (if it appears mid-text)
                            if let range = cleanOutput.range(of: marker) {
                                // If marker appears, keep only content after it
                                cleanOutput = String(cleanOutput[range.upperBound...])
                            }
                            // Also remove the marker itself if it appears anywhere
                            cleanOutput = cleanOutput.replacingOccurrences(of: marker, with: "")
                        }
                        
                        // Remove Markdown code fencing if model mimicked the prompt format
                        let codeFencePatterns = [
                            "```text",
                            "```",
                            "```markdown",
                            "```plaintext"
                        ]
                        for pattern in codeFencePatterns {
                            cleanOutput = cleanOutput.replacingOccurrences(of: pattern, with: "")
                        }
                        
                        // Remove common prompt instruction phrases that might leak into output
                        // Only remove if they appear as standalone lines or at the very start
                        let promptPhrases = [
                            "请用中文简要总结以下文本",
                            "请用中文解释这段代码的功能",
                            "请用中文润色以下文本",
                            "请将以下内容翻译成中文",
                            "重要要求：",
                            "Important requirements:",
                            "只输出",
                            "不要输出",
                            "不要重复",
                            "直接输出",
                            "Only output",
                            "Do not output",
                            "Do not repeat",
                            "Output directly"
                        ]
                        
                        // Remove prompt phrases that appear at the start of lines (only short lines)
                        let lines = cleanOutput.components(separatedBy: .newlines)
                        var cleanedLines: [String] = []
                        for line in lines {
                            var cleanedLine = line.trimmingCharacters(in: .whitespaces)
                            
                            // Skip lines that are just prompt phrases (short lines that start with prompt phrases)
                            var isPromptLine = false
                            if cleanedLine.count < 100 { // Only check short lines
                                for phrase in promptPhrases {
                                    if cleanedLine.hasPrefix(phrase) {
                                        isPromptLine = true
                                        break
                                    }
                                }
                            }
                            
                            if !isPromptLine && !cleanedLine.isEmpty {
                                cleanedLines.append(cleanedLine)
                            } else if cleanedLine.isEmpty && !cleanedLines.isEmpty {
                                // Preserve empty lines between content
                                cleanedLines.append("")
                            }
                        }
                        
                        cleanOutput = cleanedLines.joined(separator: "\n")
                        
                        // Remove any remaining prompt-like content at the start
                        cleanOutput = cleanOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Remove content that exactly matches the original input (if model repeated it)
                        // This helps prevent showing the original content as part of the response
                        // Only check if output is suspiciously long or contains exact matches
                        let contentLines = content.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        
                        if !contentLines.isEmpty {
                            let outputLines = cleanOutput.components(separatedBy: .newlines)
                            var finalLines: [String] = []
                            
                            for outputLine in outputLines {
                                let trimmed = outputLine.trimmingCharacters(in: .whitespaces)
                                
                                // Skip empty lines
                                if trimmed.isEmpty {
                                    if !finalLines.isEmpty {
                                        finalLines.append("")
                                    }
                                    continue
                                }
                                
                                // Check if this line exactly matches an input line (likely prompt repetition)
                                // Only remove if it's an exact match and the line is not too long
                                let isExactMatch = contentLines.contains { inputLine in
                                    trimmed == inputLine && trimmed.count < 200
                                }
                                
                                // Skip if it's an exact match of input content
                                if !isExactMatch {
                                    finalLines.append(trimmed)
                                }
                            }
                            
                            if !finalLines.isEmpty {
                                cleanOutput = finalLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        
                        // Special cleanup for different actions
                        if action == .summarize {
                            // Remove common summary prefixes (both Chinese and English)
                            let separators = ["总结：", "摘要：", "总结结果：", "Summary:", "总结", "摘要"]
                            for separator in separators {
                                if let range = cleanOutput.range(of: separator) {
                                    cleanOutput = String(cleanOutput[range.upperBound...])
                                    break
                                }
                            }
                            
                            let prefixes = ["总结：", "摘要：", "总结结果：", "Summary:", "总结", "摘要"]
                            for prefix in prefixes {
                                if cleanOutput.hasPrefix(prefix) {
                                    cleanOutput = String(cleanOutput.dropFirst(prefix.count))
                                }
                                cleanOutput = cleanOutput.replacingOccurrences(of: prefix, with: "")
                            }
                            
                            // Remove duplicate content
                            let outputLines = cleanOutput.components(separatedBy: .newlines)
                            var cleanedLines: [String] = []
                            var seenContent = Set<String>()
                            
                            for line in outputLines {
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                
                                if trimmed.isEmpty {
                                    if !cleanedLines.isEmpty {
                                        cleanedLines.append("")
                                    }
                                    continue
                                }
                                
                                // Skip duplicate lines
                                let normalized = trimmed.lowercased()
                                if !seenContent.contains(normalized) {
                                    seenContent.insert(normalized)
                                    cleanedLines.append(trimmed)
                                }
                            }
                            
                            if !cleanedLines.isEmpty {
                                cleanOutput = cleanedLines.joined(separator: "\n")
                            }
                            
                            // Remove redundant whitespace
                            cleanOutput = cleanOutput.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
                        } else if action == .translate {
                            // First, detect if output contains a separator like "Translation:" and only keep content after it
                            let separators = ["中文翻译：", "翻译：", "中文：", "翻译结果：", "Translation:"]
                            for separator in separators {
                                if let range = cleanOutput.range(of: separator) {
                                    // Keep only content after the separator
                                    cleanOutput = String(cleanOutput[range.upperBound...])
                                    break // Only process the first separator found
                                }
                            }
                            
                            // Remove common translation prefixes (check both start and anywhere in text)
                            let prefixes = ["翻译：", "中文：", "翻译结果：", "Translation:", "中文翻译：", "中文翻译", "翻译结果"]
                            for prefix in prefixes {
                                // Remove from start
                                if cleanOutput.hasPrefix(prefix) {
                                    cleanOutput = String(cleanOutput.dropFirst(prefix.count))
                                }
                                // Remove from anywhere (in case model outputs it mid-text)
                                cleanOutput = cleanOutput.replacingOccurrences(of: prefix, with: "")
                            }
                            
                            // Remove placeholder text like "Example: (if available) None"
                            let placeholders = [
                                "例句（如有）没有",
                                "例句（如有） 没有",
                                "例句（如有）: 没有",
                                "例句: 没有",
                                "例句 没有"
                            ]
                            for placeholder in placeholders {
                                cleanOutput = cleanOutput.replacingOccurrences(of: placeholder, with: "")
                            }
                            
                            // Remove leading/trailing quotes if the entire output is quoted
                            if (cleanOutput.hasPrefix("\"") && cleanOutput.hasSuffix("\"")) ||
                               (cleanOutput.hasPrefix("'") && cleanOutput.hasSuffix("'")) {
                                cleanOutput = String(cleanOutput.dropFirst().dropLast())
                            }
                            
                            // Detect and remove duplicate content (if output contains original content)
                            // Check if output contains the original content and remove it
                            let originalLines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                            let outputLines = cleanOutput.components(separatedBy: .newlines)
                            
                            var cleanedLines: [String] = []
                            var seenContent = Set<String>()
                            var foundTranslationStart = false
                            
                            for line in outputLines {
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                
                                // Skip empty lines
                                if trimmed.isEmpty {
                                    if foundTranslationStart {
                                        cleanedLines.append("")
                                    }
                                    continue
                                }
                                
                                // Check if this line matches original content
                                let isOriginalContent = originalLines.contains { originalLine in
                                    !originalLine.isEmpty && trimmed.contains(originalLine)
                                }
                                
                                // Skip if this line looks like original English content
                                // Check if line contains mostly English characters and common English words
                                let hasChinese = trimmed.range(of: "[\u{4e00}-\u{9fff}]", options: .regularExpression) != nil
                                let englishWordPattern = "\\b(the|is|are|was|were|a|an|and|or|but|in|on|at|to|for|of|with|by|command|instruction|answer)\\b"
                                let hasEnglishWords = trimmed.range(of: englishWordPattern, options: [.regularExpression, .caseInsensitive]) != nil
                                
                                // Skip if it's original content or English-only content without Chinese
                                if isOriginalContent || (!hasChinese && hasEnglishWords && trimmed.count > 5) {
                                    continue
                                }
                                
                                // Mark that we've found translation content
                                if hasChinese || trimmed.hasPrefix("**") {
                                    foundTranslationStart = true
                                }
                                
                                // Only add lines after we've found translation content
                                if foundTranslationStart {
                                    // Skip duplicate lines
                                    let normalized = trimmed.lowercased()
                                    if !seenContent.contains(normalized) {
                                        seenContent.insert(normalized)
                                        cleanedLines.append(trimmed)
                                    }
                                }
                            }
                            
                            // If we found cleaned lines, use them; otherwise keep original cleaned output
                            if !cleanedLines.isEmpty {
                                cleanOutput = cleanedLines.joined(separator: "\n")
                            }
                            
                            // Remove redundant whitespace but preserve intentional formatting
                            cleanOutput = cleanOutput.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
                        } else if action == .explainCode || action == .polish {
                            // Remove common prefixes for explain and polish (both Chinese and English)
                            let prefixes: [String]
                            if action == .explainCode {
                                prefixes = ["解释：", "说明：", "代码解释：", "Explanation:", "解释", "说明"]
                            } else {
                                prefixes = ["润色：", "修改后：", "润色结果：", "Polished:", "润色", "修改后"]
                            }
                            
                            for prefix in prefixes {
                                if let range = cleanOutput.range(of: prefix) {
                                    cleanOutput = String(cleanOutput[range.upperBound...])
                                    break
                                }
                                if cleanOutput.hasPrefix(prefix) {
                                    cleanOutput = String(cleanOutput.dropFirst(prefix.count))
                                }
                                cleanOutput = cleanOutput.replacingOccurrences(of: prefix, with: "")
                            }
                            
                            // Remove duplicate content
                            let outputLines = cleanOutput.components(separatedBy: .newlines)
                            var cleanedLines: [String] = []
                            var seenContent = Set<String>()
                            
                            for line in outputLines {
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                
                                if trimmed.isEmpty {
                                    if !cleanedLines.isEmpty {
                                        cleanedLines.append("")
                                    }
                                    continue
                                }
                                
                                // Skip duplicate lines
                                let normalized = trimmed.lowercased()
                                if !seenContent.contains(normalized) {
                                    seenContent.insert(normalized)
                                    cleanedLines.append(trimmed)
                                }
                            }
                            
                            if !cleanedLines.isEmpty {
                                cleanOutput = cleanedLines.joined(separator: "\n")
                            }
                            
                            // Remove redundant whitespace
                            cleanOutput = cleanOutput.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
                        }
                        
                        cleanOutput = cleanOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                        // Clean up temp file before resuming
                        cleanupTempFile()
                        
                        if cleanOutput.isEmpty {
                             continuation.resume(returning: "[Model returned empty response]")
                        } else {
                             continuation.resume(returning: cleanOutput)
                        }
                    } else {
                        // Clean up temp file before resuming with error
                        cleanupTempFile()
                        continuation.resume(throwing: LLMError.processFailed(reason: "Exit \(process.terminationStatus): \(errOutput)"))
                    }
                } catch {
                    // Clean up temp file before resuming with error
                    cleanupTempFile()
                    continuation.resume(throwing: error)
                }
            }
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
            default: return "English" // Default to English
            }
        }
        
        return "English" // Default fallback
    }
    
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

重要要求：
1. 只输出翻译后的中文内容，不要输出原始英文内容
2. 不要输出"中文翻译："、"翻译："、"Translation:"等任何前缀
3. 如果是单词，格式：
   **单词** [音标]
   - **词性**: 词性
   - **释义**: 中文释义
   - **例句**: 例句（如有，没有则省略此项）
4. 如果是句子或段落，直接输出中文翻译，不要添加任何格式标记
5. 不要重复输出相同的内容
"""
        case "English":
            return """
Please translate the following content to English.

Important requirements:
1. Only output the translated English content, do not output the original content
2. Do not output prefixes like "Translation:" or "English:"
3. If it's a word, format:
   **word** [phonetic]
   - **Part of speech**: ...
   - **Definition**: ...
   - **Example**: ... (if available, omit if not)
4. If it's a sentence or paragraph, output the English translation directly without format markers
5. Do not repeat the same content
"""
        case "Japanese":
            return """
以下の内容を日本語に翻訳してください。

重要な要件：
1. 翻訳された日本語の内容のみを出力し、元の内容を出力しないでください
2. 「日本語翻訳：」や「翻訳：」などの接頭辞を出力しないでください
3. 単語の場合は、形式：
   **単語** [音声記号]
   - **品詞**: ...
   - **意味**: ...
   - **例文**: ...（ある場合は、ない場合は省略）
4. 文や段落の場合は、フォーマットマーカーなしで日本語翻訳を直接出力してください
5. 同じ内容を繰り返さないでください
"""
        case "Korean":
            return """
다음 내용을 한국어로 번역해 주세요.

중요한 요구사항:
1. 번역된 한국어 내용만 출력하고 원본 내용을 출력하지 마세요
2. "한국어 번역:" 또는 "번역:"과 같은 접두사를 출력하지 마세요
3. 단어인 경우 형식:
   **단어** [음성 기호]
   - **품사**: ...
   - **의미**: ...
   - **예문**: ... (있는 경우, 없는 경우 생략)
4. 문장이나 단락인 경우 형식 마커 없이 한국어 번역을 직접 출력하세요
5. 동일한 내용을 반복하지 마세요
"""
        default:
            return """
Please translate the following content to \(language).

Important requirements:
1. Only output the translated content, do not output the original content
2. Do not output prefixes
3. Output the translation directly without format markers
4. Do not repeat the same content
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
            // For other languages, use English instruction but mention keeping original language
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
    
    // MARK: - Ollama Inference
    
    private func generateResponseOllama(prompt: String) async throws -> String {
        var request = URLRequest(url: ollamaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.invalidResponse
        }
        
        struct OllamaResponse: Decodable {
            let response: String
        }
        
        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return result.response
    }
    
    private func constructPrompt(for action: AIAction, content: String) -> String {
        switch action {
        case .summarize:
            return "Summarize the following text efficiently:\n\n\(content)"
        case .translate:
            return "Translate the following text to English (if it's not) or Chinese (if it is English), maintaining the tone:\n\n\(content)"
        case .explainCode:
            return "Explain what this code does simply:\n\n\(content)"
        case .polish:
            return "Fix grammar and improve the tone of this text:\n\n\(content)"
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
    case serviceUnavailable
    case invalidResponse
    case decodingError
    case binaryNotFound(path: String)
    case modelNotFound(path: String)
    case processFailed(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Ollama service is not reachable."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .decodingError:
            return "Failed to decode AI response."
        case .binaryNotFound(let path):
            return "llama-cli binary not found at: \(path)"
        case .modelNotFound(let path):
            return "Model file not found at: \(path)"
        case .processFailed(let reason):
            return "Process failed: \(reason)"
        }
    }
}
