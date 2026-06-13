# VeloxClip

A powerful clipboard manager for macOS that helps you manage, search, and transform your clipboard history with intelligent on-device features. Includes built-in screenshot capture and professional image editing tools.

## ✨ Features

### 📋 Core Clipboard Management
- **Automatic History Tracking**: Seamlessly captures and stores all clipboard content (text, images, RTF, files, colors)
- **Smart Deduplication**: Prevents duplicate entries within a 5-second window
- **Configurable History Limit**: Set your preferred history size (default: 100 items)
- **Source App Tracking**: Know where each clipboard item came from
- **Quick Paste**: Fast paste to previous application with customizable global shortcut
- **Favorites System**: Mark important items as favorites for quick access
- **Custom Tags**: Add custom tags to favorite items for better organization and search
- **Single Instance**: Automatically prevents multiple instances from running simultaneously

### 📚 Paste Stack (Sequential Paste Queue)
- **Stage Multiple Items**: Queue several history items (press `Space` or click the ⊕ on a row) and paste them in order
- **Just Cmd+V**: Each plain `Cmd+V` in the target app pastes the next item — no extra shortcut to learn
- **Progress HUD**: A floating, non-focus-stealing panel shows the queue position; pick its corner in Settings (defaults to bottom center) or drag it anywhere
- **Auto-Pause**: Copying something new while a queue is active pauses it so it never fights you for the clipboard — resume from the HUD or menu bar
- **Menu Bar Controls**: Resume/Cancel the queue from the menu bar, even with the HUD hidden
- **Clipboard Restore**: Your pre-queue clipboard is restored when the stack finishes

### 🔎 Screen Text Capture (OCR Anywhere)
- **One-Step Text Grab**: Press `F2`, select any screen region, and the recognized text lands straight on the clipboard — no intermediate image, no extra clicks
- **QR & Barcode Decode**: Frame a QR/barcode and its payload is copied instead of the surrounding text
- **Fully On-Device**: Uses Apple Vision (Chinese + English), nothing leaves your Mac
- **Independent of F1**: The F1 screenshot flow (image + background OCR) is unchanged — F2 is for when you want the *text*, not the picture

### 🤖 On-Device Intelligence
- **OCR Text Recognition**: Automatically extracts text from images using Apple Vision framework — fully local
- **Text Summary**: Quick extractive summaries of long text content
- **Semantic Search**: Find clipboard items by meaning, not just keywords (Natural Language framework, local)

### 🔍 Advanced Search
- **Keyword Search**: Fast exact match search across content, type, source app, and tags
- **Semantic Search**: On-device search that understands context and meaning
- **Type Filter**: One-tap filter chips above the list — All / Text / Image / File — that stack on top of search and the favorites view
- **Tag-based Search**: Search by custom tags or auto-detected content type tags (json, table, url, code, markdown, etc.)
- **Content Type Tags**: Automatically generated tags based on detected content types for better organization
- **Favorites Prioritization**: Favorite items appear first in search results
- **Search Debouncing**: Optimized performance with intelligent caching
- **Real-time Filtering**: Instant results as you type

### ⭐ Favorites & Organization
- **Favorites View**: Toggle between favorites and full history with star button or Tab key
- **Permanent Preservation**: Favorite items are never deleted by history limit
- **Auto-Tagging**: Automatically detects content type and adds corresponding tags:
  - Content types: `json`, `table`, `url`, `datetime`, `code`, `markdown`, `longtext`
  - Item types: `image`, `file`, `color`
  - Tags are added automatically when previewing items
- **Custom Tags**: Add personalized tags to favorite items for better categorization
- **Colorful Tags**: Custom tags automatically get vibrant, name-based colors for easy identification
- **Tag Management**: Easily add or remove tags from favorite items in the preview pane
- **Smart History Limit**: Only non-favorite items count toward history limit, ensuring favorites are always preserved

### 📸 Screenshot & Image Tools
- **Area Screenshot**: Capture area screenshots using macOS native tool (default: F1)
- **Paste Image**: Display floating image window from clipboard (default: F3)
- **Image Editor**: Professional screenshot editing with multiple tools:
  - **Drawing Tools**: Pen, Arrow, Rectangle, Circle, Line
  - **Highlight Tool**: Semi-transparent highlighting for emphasis
  - **Text Tool**: Add text annotations with customizable font size
  - **Mosaic Tool**: Blur sensitive areas with mosaic effect
  - **Eraser Tool**: Remove unwanted annotations
- **Edit Workflow**: After taking a screenshot, access history and click "Edit" button on image items
- **Save & Copy**: Save edited images or copy directly to clipboard

### 🎨 User Interface
- **Spotlight-Style Overlay**: Beautiful, modern interface that appears over any application
- **Enhanced Preview Components**: Specialized preview views for different content types:
  - **JSON Preview**: Formatted JSON with syntax highlighting and validation
  - **Table Preview**: Interactive table view with delimiter detection (CSV, TSV, etc.)
  - **URL Preview**: Link preview with validation and quick actions (open, copy, QR code)
  - **DateTime Preview**: Multiple date/time format display and conversion
  - **Code Preview**: Syntax highlighting for 16+ languages with line numbers and formatting
  - **Color Preview**: Visual color display with multiple format outputs (HEX, RGB, HSL, etc.)
  - **File Preview**: File information display with quick actions (reveal, open)
  - **Image Preview**: Enhanced image view with metadata (dimensions, format, size, color space)
  - **Markdown Preview**: Rich Markdown rendering with full formatting support
  - **Text Summary**: Intelligent text summarization for long content
- **Auto-Tagging**: Automatically adds content type tags (json, table, url, code, markdown, etc.) when previewing items
- **Markdown Rendering**: Rich Markdown support in preview pane
- **Image Preview**: View images with OCR text extraction and copy functionality
- **Keyboard Navigation**: Full keyboard support for efficient workflow
- **View Switching**: Toggle between favorites and history with Tab key or star button
- **Tag Editor**: Intuitive tag editing interface in preview pane for favorite items
- **Customizable Shortcuts**: Set your preferred global hotkey (default: Cmd+Shift+V)
- **Screenshot Shortcuts**: Customize screenshot, screen text capture, and paste image shortcuts (defaults: F1, F2, F3)

### 🔒 Privacy & Performance
- **100% On-Device**: OCR, semantic search, and content detection all run locally — no API keys, no network calls
- **No Cloud Sync**: Your clipboard data stays on your Mac
- **Efficient Caching**: Smart caching for embeddings and search results
- **Memory Optimized**: Designed for performance with large clipboard histories

## 🛠️ Technology Stack

- **Language**: Swift 6.0
- **Framework**: SwiftUI
- **AI/ML**: 
  - Apple Vision Framework (OCR)
  - Natural Language Framework (Embeddings, Language Detection)
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

### Download from GitHub Releases

If you downloaded the app from GitHub and see a "damaged", "unidentified developer", or "危险应用" (dangerous app) warning:

**Method 1: Control+Click (Recommended)**
1. **Control+Click** (or right-click) on `VeloxClip.app`
2. Select **"Open"**
3. Click **"Open"** in the security dialog

**Method 2: System Settings (If you see "危险应用" warning)**
1. Open **System Settings** (系统设置)
2. Go to **Privacy & Security** (隐私与安全性)
3. Scroll down to the **Security** (安全性) section
4. You should see a message about VeloxClip being blocked
5. Click **"仍要打开"** (Still Open) or **"Open Anyway"** button

**Method 3: Terminal Command**
Run this command in Terminal:
```bash
xattr -cr VeloxClip.app
```

**Note:** This is normal for open-source apps without paid Apple Developer certificates. The app is safe - macOS just needs your confirmation the first time.

## 🚀 Usage

### Basic Operations

1. **Open Clipboard History**: Press `Cmd+Shift+V` (or your custom shortcut)
2. **Search**: Type to search through your clipboard history
3. **Navigate**: Use arrow keys to move through items
4. **Paste**: Press Enter to paste the selected item to the previous application
5. **Preview**: View detailed content in the preview pane
6. **Filter by Type**: Use the All / Text / Image / File chips above the list to narrow results

### Paste Stack (Sequential Paste Queue)

1. **Stage Items**: With the search box empty, press `Space` on the selected row (or click the ⊕ that appears on hover) to add it to the queue — a numbered badge (①②③) shows its order
2. **Start the Queue**: Close the overlay (Esc) — the floating Paste Stack HUD appears
3. **Paste in Order**: In any app, press `Cmd+V` repeatedly — each press pastes the next item and advances the HUD
4. **Pause/Resume**: Copying something else auto-pauses the queue; resume from the HUD's ▶ button or the menu bar
5. **Exit**: Click ✕ on the HUD, or use "Cancel Paste Queue" in the menu bar
6. **HUD Position**: Set the corner in Preferences → General → Paste Stack (or drag the HUD anywhere); disable it entirely to show progress in the menu bar instead

### Screen Text Capture (OCR Anywhere)

1. **Capture**: Press `F2` (customizable) and drag to select any region of the screen
2. **Done**: The recognized text is copied to the clipboard instantly and added to history — a brief toast confirms how many characters were captured
3. **QR / Barcode**: If the region contains a QR or barcode, its payload is copied instead of the surrounding text
4. **Cancel**: Press `Esc` during selection — nothing is captured

### Screenshot & Image Editing

1. **Take Screenshot**: Press `F1` (or your custom shortcut) to capture area screenshot
2. **View History**: After screenshot, clipboard history window opens automatically
3. **Edit Image**: Click "Edit" button on any image item in the preview pane
4. **Edit Tools**: 
   - Select drawing tools (Pen, Arrow, Rectangle, Circle, Line, Highlight)
   - Add text annotations with customizable size
   - Apply mosaic effect to blur sensitive areas
   - Use eraser to remove unwanted annotations
5. **Save or Copy**: Save edited image to file or copy to clipboard
6. **Paste Image**: Press `F3` (or your custom shortcut) to display floating image from clipboard

### Favorites & Tags

1. **Add to Favorites**: Click the star icon in the preview pane to favorite an item
2. **View Favorites**: Click the star button in the search bar or press Tab to switch to favorites view
3. **Auto-Tagging**: Content type tags are automatically added when previewing items:
   - JSON content → `json` tag
   - Table data → `table` tag
   - URLs → `url` tag
   - Date/time → `datetime` tag
   - Code snippets → `code` tag
   - Markdown → `markdown` tag
   - Long text → `longtext` tag
   - Images → `image` tag
   - Files → `file` tag
   - Colors → `color` tag
4. **Add Custom Tags**: 
   - Favorite an item first
   - Click the edit button (pencil icon) in the Tags section
   - Type a tag name and press Enter or click the plus button
5. **Remove Tags**: In edit mode, click the X button on any tag to remove it
6. **Search by Tags**: Type a tag name in the search box to find all items with that tag

### On-Device Intelligence

- **OCR**: Automatically extracts text from images. Click "Copy Text" button in preview to copy OCR results
- **Summarize**: Generate a quick extractive summary for long text in the preview pane
- **Text Tools**: Convert case (UPPERCASE/lowercase) or clean up whitespace via the Tools menu

### Settings

Access settings via:
- Menu bar icon → Preferences
- Keyboard shortcut: `Cmd+,`

Configure:
- History limit
- Global shortcut (default: Cmd+Shift+V)
- Screenshot shortcut (default: F1)
- Screen text capture shortcut (default: F2)
- Paste image shortcut (default: F3)
- Paste Stack HUD: show/hide and position (defaults to bottom center)
- Launch at login

## 🎯 Use Cases

- **Developers**: 
  - Quick access to code snippets with syntax highlighting
  - JSON and table data preview with formatted display
  - Auto-tagged code snippets (`code`, `json` tags) for easy search
  - Capture and annotate screenshots of bugs or UI issues
- **Writers**: 
  - Manage quotes, references, and research snippets
  - Markdown preview for formatted text
  - Auto-tagged long text (`longtext`, `markdown` tags)
  - Capture and highlight important text from documents
- **Designers**: 
  - Track color codes with visual color preview and multiple format outputs
  - Image assets with detailed metadata
  - Auto-tagged colors (`color` tag) and images (`image` tag)
  - Edit screenshots with annotations and highlights
- **Researchers**: 
  - Organize copied text, citations, and notes
  - Table data preview for structured information
  - Auto-tagged content types for easy categorization
  - Capture and annotate research materials
- **Multilingual Users**: 
  - Manage content in multiple languages — semantic search understands both English and Chinese
  - URL preview for quick link access
  - Auto-tagged URLs (`url` tag) for easy access
- **Project Managers**: 
  - Keep important information organized with favorites and custom tags
  - DateTime preview for meeting schedules
  - Auto-tagged content types for different projects
  - Capture and annotate meeting notes or project screenshots
- **Content Creators**: 
  - Capture screenshots, add annotations, and quickly paste images
  - File preview for asset management
  - Auto-tagged files (`file` tag) for easy organization

## 🔧 Configuration

### Global Shortcuts
- **Toggle Window**: Default `Cmd+Shift+V`
- **Area Screenshot**: Default `F1`
- **Screen Text Capture**: Default `F2`
- **Paste Image**: Default `F3`
- **Paste Stack**: Stage with `Space` (or ⊕) in the overlay, paste with plain `Cmd+V`
- Customize in Preferences → Shortcuts Settings
- Supports modifier keys: Cmd, Shift, Option, Control
- Supports function keys (F1-F12) without modifiers

### History Limit
Default: 100 items
- Adjust in Preferences → General Settings
- Range: 10-1000 items
- **Smart Limit**: Only non-favorite items count toward the limit
- Favorite items are permanently preserved regardless of history limit
- This ensures your important items are never accidentally deleted

## 📝 File Structure

```
VeloxClip/
├── VeloxClip/
│   ├── App/              # Application entry point and window management
│   ├── Models/            # Data models (ClipboardItem, AppSettings, DatabaseManager)
│   ├── Services/          # Core services
│   │   ├── AIService.swift    # On-device OCR + embeddings
│   │   ├── ScreenshotEditor/  # Screenshot editing (EditorModels, EditorState, ScreenshotEditorService, ScreenshotEditorView)
│   │   ├── ClipboardMonitor.swift
│   │   ├── ScreenshotService.swift
│   │   ├── PasteImageService.swift
│   │   ├── PasteStackService.swift    # Sequential paste queue (Paste Stack)
│   │   ├── TextCaptureService.swift   # Screen text capture / OCR anywhere (F2)
│   │   ├── ContentDetectionService.swift
│   │   ├── ShortcutManager.swift
│   │   └── ErrorHandler.swift
│   ├── Views/             # SwiftUI views
│   │   ├── PreviewComponents/  # Enhanced preview components
│   │   │   ├── CodePreviewView.swift      # Code syntax highlighting
│   │   │   ├── ColorPreviewView.swift     # Color display and formats
│   │   │   ├── DateTimePreviewView.swift  # Date/time formats
│   │   │   ├── FilePreviewView.swift     # File information
│   │   │   ├── ImagePreviewView.swift    # Enhanced image preview
│   │   │   ├── JSONPreviewView.swift     # JSON formatting
│   │   │   ├── TablePreviewView.swift    # Table data display
│   │   │   ├── TextSummaryView.swift     # Text summarization
│   │   │   └── URLPreviewView.swift      # URL preview and actions
│   │   ├── MainView.swift
│   │   ├── PreviewView.swift
│   │   ├── SettingsView.swift
│   │   └── ...
│   └── Resources/         # App resources (icons, assets)
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

## 📧 Support

For issues, feature requests, or questions, please open an issue on GitHub.

---

**Made with ❤️ for macOS users who value productivity and privacy**

