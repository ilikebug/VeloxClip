import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 500, height: 350)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var llmService = LLMService.shared
    @State private var modelLoadError: String?
    
    // Helper function to explicitly save API key
    private func saveAPIKey(_ apiKey: String) {
        Task {
            do {
                try await DatabaseManager.shared.setSetting(key: "openRouterAPIKey", value: apiKey)
                print("✅ OpenRouter API Key explicitly saved (length: \(apiKey.count))")
                
                // Load models when API key is saved
                if !apiKey.isEmpty {
                    await loadModels(apiKey: apiKey)
                }
            } catch {
                print("❌ Failed to explicitly save OpenRouter API Key: \(error)")
            }
        }
    }
    
    private func loadModels(apiKey: String) async {
        guard !apiKey.isEmpty else { return }
        
        do {
            modelLoadError = nil
            try await llmService.fetchAvailableModels(apiKey: apiKey)
            print("✅ Loaded \(llmService.availableModels.count) models from OpenRouter")
        } catch {
            print("❌ Failed to load models: \(error)")
            modelLoadError = error.localizedDescription
        }
    }
    
    var body: some View {
        Form {
            Section {
                Picker("History Limit", selection: $settings.historyLimit) {
                    Text("50 items").tag(50)
                    Text("100 items").tag(100)
                    Text("500 items").tag(500)
                    Text("1000 items").tag(1000)
                }
                .help("Maximum number of items to keep in history")
                
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .help("Automatically start Velox Clip when you log in")
            }
            
            Section("AI Settings") {
                HStack {
                    SecureField("OpenRouter API Key", text: $settings.openRouterAPIKey)
                        .help("Get your free API key from https://openrouter.ai/keys")
                        .onSubmit {
                            // Explicitly save when user presses Enter
                            saveAPIKey(settings.openRouterAPIKey)
                        }
                        .onChange(of: settings.openRouterAPIKey) { _, newValue in
                            // Save immediately when changed
                            print("🔑 OpenRouter API Key changed, length: \(newValue.count)")
                            saveAPIKey(newValue)
                            
                            // Load models when API key changes
                            if !newValue.isEmpty {
                                Task {
                                    await loadModels(apiKey: newValue)
                                }
                            }
                        }
                    
                    // Save button for explicit save
                    Button(action: {
                        saveAPIKey(settings.openRouterAPIKey)
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Save API Key")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if llmService.isLoadingModels {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = modelLoadError {
                        Text("Failed to load models: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    if llmService.availableModels.isEmpty && !llmService.isLoadingModels {
                        // Fallback to default models if API key not set or models failed to load
                        Picker("AI Model", selection: $settings.openRouterModel) {
                            Text("DeepSeek R1 Chimera (Free)").tag("tngtech/deepseek-r1t2-chimera:free")
                            Text("DeepSeek Chat (Free)").tag("deepseek/deepseek-chat:free")
                            Text("DeepSeek Coder (Free)").tag("deepseek/deepseek-coder:free")
                        }
                        .help("Enter API key to see all available models")
                    } else {
                        Picker("AI Model", selection: $settings.openRouterModel) {
                            // Show current selection if it's not in the list
                            if !llmService.availableModels.contains(where: { $0.id == settings.openRouterModel }) {
                                Text("\(settings.openRouterModel) (Current)").tag(settings.openRouterModel)
                            }
                            
                            ForEach(llmService.availableModels) { model in
                                let isFree = model.id.contains(":free") || 
                                            (model.pricing?.prompt == "0" && model.pricing?.completion == "0")
                                let displayName = isFree ? "\(model.name) (Free)" : model.name
                                
                                Text(displayName).tag(model.id)
                            }
                        }
                        .help("Select the AI model to use for AI features")
                    }
                    
                    if !settings.openRouterAPIKey.isEmpty && !llmService.isLoadingModels && llmService.availableModels.isEmpty {
                        Button("Refresh Models") {
                            Task {
                                await loadModels(apiKey: settings.openRouterAPIKey)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                
                Picker("AI Response Language", selection: $settings.aiResponseLanguage) {
                    Text("Chinese (中文)").tag("Chinese")
                    Text("English").tag("English")
                    Text("日本語 (Japanese)").tag("Japanese")
                    Text("한국어 (Korean)").tag("Korean")
                    Text("Español (Spanish)").tag("Spanish")
                    Text("Français (French)").tag("French")
                    Text("Deutsch (German)").tag("German")
                }
                .help("Language for AI responses (summary, code explanation, etc.)")
            }
            
            Section("Maintenance") {
                Button("Clear Image & Analysis Caches") {
                    CacheManager.shared.clearAllCaches()
                }
                .help("Clear background caches for OCR, embeddings, and content detection. Doesn't delete your history.")
                
                Button("Clear All History") {
                    ClipboardStore.shared.clearAll()
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .formStyle(.grouped)
        .onAppear {
            // Load models when view appears if API key is set
            if !settings.openRouterAPIKey.isEmpty && llmService.availableModels.isEmpty {
                Task {
                    await loadModels(apiKey: settings.openRouterAPIKey)
                }
            }
        }
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Toggle Window")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.globalShortcut)
                        .frame(width: 200, height: 24)
                }
                Text("Click the button and press your desired key combination")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                HStack {
                    Text("Area Screenshot")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.screenshotShortcut)
                        .frame(width: 200, height: 24)
                }
                Text("Capture area screenshot (default: F1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                HStack {
                    Text("Paste Image")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.pasteImageShortcut)
                        .frame(width: 200, height: 24)
                }
                Text("Show floating image from clipboard (default: F3)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .formStyle(.grouped)
        .onChange(of: settings.globalShortcut) { _, newValue in
            ShortcutManager.shared.updateShortcut(newValue)
        }
        .onChange(of: settings.screenshotShortcut) { _, newValue in
            ShortcutManager.shared.updateScreenshotShortcut(newValue)
        }
        .onChange(of: settings.pasteImageShortcut) { _, newValue in
            ShortcutManager.shared.updatePasteImageShortcut(newValue)
        }
    }
}
