# VeloxClip

A powerful, AI-enhanced clipboard manager for macOS that helps you manage, search, and transform your clipboard history with intelligent features.

## ✨ Features

### 📋 Core Clipboard Management
- **Automatic History Tracking**: Seamlessly captures and stores all clipboard content (text, images, RTF, files, colors)
- **Smart Deduplication**: Prevents duplicate entries within a 5-second window
- **Configurable History Limit**: Set your preferred history size (default: 100 items)
- **Source App Tracking**: Know where each clipboard item came from
- **Quick Paste**: Fast paste to previous application with customizable global shortcut

### 🤖 AI-Powered Features
- **OCR Text Recognition**: Automatically extracts text from images using Apple Vision framework
- **Text Summarization**: Get concise summaries of long text content
- **Translation**: Translate text to multiple languages (Chinese, English, Japanese, Korean, Spanish, French, German)
- **Code Explanation**: Understand code snippets with AI-generated explanations
- **Text Polishing**: Improve and optimize text while preserving the original language
- **Semantic Search**: Find clipboard items by meaning, not just keywords

### 🔍 Advanced Search
- **Keyword Search**: Fast exact match search across content, type, source app, and tags
- **Semantic Search**: AI-powered search that understands context and meaning
- **Search Debouncing**: Optimized performance with intelligent caching
- **Real-time Filtering**: Instant results as you type

### 🎨 User Interface
- **Spotlight-Style Overlay**: Beautiful, modern interface that appears over any application
- **Markdown Rendering**: Rich Markdown support in preview pane
- **Image Preview**: View images with OCR text extraction and copy functionality
- **Keyboard Navigation**: Full keyboard support for efficient workflow
- **Customizable Shortcuts**: Set your preferred global hotkey (default: Cmd+Shift+V)

### 🔒 Privacy & Performance
- **Local Processing**: All AI features run locally using on-device models
- **No Cloud Sync**: Your clipboard data stays on your Mac
- **Efficient Caching**: Smart caching for embeddings and search results
- **Memory Optimized**: Designed for performance with large clipboard histories

## 🛠️ Technology Stack

- **Language**: Swift 6.0
- **Framework**: SwiftUI
- **AI/ML**: 
  - Apple Vision Framework (OCR)
  - Natural Language Framework (Embeddings, Language Detection)
  - Local LLM via llama-cli (Qwen2.5 model)
- **Platform**: macOS 14.0+

## 📦 Installation

### Prerequisites
- macOS 14.0 or later
- Xcode Command Line Tools
- Swift 6.0+

### Build from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/VeloxClip.git
cd VeloxClip
```

2. Build the application:
```bash
swift build -c release
```

3. Create the app bundle:
```bash
./build_app.sh
```

4. Copy `VeloxClip.app` to your Applications folder:
```bash
cp -R VeloxClip.app /Applications/
```

### LLM Setup (Optional, for AI features)

1. Download the Qwen2.5 model and place it in the `LLM/` directory
2. Download `llama-cli` binary and place it in the `LLM/` directory
3. The app will automatically use these resources when available

## 🚀 Usage

### Basic Operations

1. **Open Clipboard History**: Press `Cmd+Shift+V` (or your custom shortcut)
2. **Search**: Type to search through your clipboard history
3. **Navigate**: Use arrow keys to move through items
4. **Paste**: Press Enter to paste the selected item to the previous application
5. **Preview**: View detailed content in the preview pane

### AI Features

- **OCR**: Automatically extracts text from images. Click "Copy Text" button in preview to copy OCR results
- **Summarize**: Select text and use AI actions to get summaries
- **Translate**: Translate clipboard content to your preferred language
- **Explain Code**: Get explanations for code snippets
- **Polish Text**: Improve text quality while keeping the original language

### Settings

Access settings via:
- Menu bar icon → Preferences
- Keyboard shortcut: `Cmd+,`

Configure:
- History limit
- Global shortcut
- AI response language
- Launch at login

## 🎯 Use Cases

- **Developers**: Quick access to code snippets, error messages, and terminal outputs
- **Writers**: Manage quotes, references, and research snippets
- **Designers**: Track color codes, image assets, and design notes
- **Researchers**: Organize copied text, citations, and notes
- **Multilingual Users**: Translate and manage content in multiple languages

## 🔧 Configuration

### Global Shortcut
Default: `Cmd+Shift+V`
- Customize in Preferences → General Settings
- Supports modifier keys: Cmd, Shift, Option, Control

### History Limit
Default: 100 items
- Adjust in Preferences → General Settings
- Range: 10-1000 items

### AI Response Language
Choose from:
- Chinese (中文)
- English
- Japanese (日本語)
- Korean (한국어)
- Spanish (Español)
- French (Français)
- German (Deutsch)

## 📝 File Structure

```
VeloxClip/
├── VeloxClip/
│   ├── App/              # Application entry point and window management
│   ├── Models/            # Data models (ClipboardItem, AppSettings)
│   ├── Services/          # Core services (AI, LLM, Clipboard monitoring)
│   ├── Views/             # SwiftUI views (MainView, PreviewView, Settings)
│   └── Resources/         # App resources (icons, assets)
├── LLM/                   # LLM model files (optional)
├── build_app.sh           # Build script
├── generate_icon.sh       # Icon generation script
└── Package.swift          # Swift package configuration
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built with SwiftUI and Apple's native frameworks
- Uses Apple Vision Framework for OCR
- Local LLM powered by llama-cli and Qwen2.5 model

## 📧 Support

For issues, feature requests, or questions, please open an issue on GitHub.

---

**Made with ❤️ for macOS users who value productivity and privacy**

