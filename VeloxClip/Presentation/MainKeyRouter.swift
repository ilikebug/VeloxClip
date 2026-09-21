import Foundation

/// What the overlay should do with a key press.
///
/// `.passThrough` means "don't consume it" — the event falls through to the
/// focused field so plain typing still reaches search / tag / palette.
enum MainKeyAction: Equatable {
    case passThrough
    case copySelection
    case openPalette
    case closeDetail
    case stageSelection
    case pasteSelection
    case moveSelection(by: Int)
    case openDetail
    case pasteRow(index: Int)
    case clearSearch
    case closeOverlay
    case switchTab
}

/// Everything the router needs to know about the moment of the key press.
struct MainKeyContext {
    var keyCode: UInt16
    /// `charactersIgnoringModifiers`, lowercased.
    var characters: String?
    var isCommandPressed: Bool
    /// The overlay is the key window. False for Settings and other windows.
    var isOverlayKeyWindow: Bool
    var isPalettePresented: Bool
    var isDetailPresented: Bool
    /// The caret is inside an editable field or a selectable preview.
    var isEditingText: Bool
    /// The focused text view holds a non-empty selection.
    var hasTextSelection: Bool
    /// An IME composition is in progress — never steal keys mid-composition.
    var isComposingText: Bool
    var hasSelection: Bool
    var isSearchTextEmpty: Bool
    var visibleItemCount: Int
}

/// The overlay's focus-independent key routing, as a pure function.
///
/// This was a ~120-line `switch` inside a 773-line view, so the decisions that
/// actually matter — which keys are stolen from the search field, what happens
/// mid-IME-composition, ⌘C vs. native copy-selection — had no tests. Only four
/// one-line boolean helpers had been extracted.
enum MainKeyRouter {
    // left=123 right=124 down=125 up=126 return=36 keypadEnter=76 esc=53 tab=48 space=49
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let tab: UInt16 = 48
    static let space: UInt16 = 49

    static func route(_ ctx: MainKeyContext) -> MainKeyAction {
        // Only handle when OUR overlay is the key window (don't hijack Settings).
        guard ctx.isOverlayKeyWindow else { return .passThrough }
        // While the palette is open it handles its own keys (typing + ↑↓/⏎/Esc).
        if ctx.isPalettePresented { return .passThrough }

        let isReturn = ctx.keyCode == returnKey || ctx.keyCode == keypadEnter

        // ⌘C copies the detail/selected item with its full payload, in both list
        // and detail mode — makes the palette's ⌘C hint truthful. In list mode
        // the search field is the permanent first responder, so honoring
        // `isEditingText` blindly would route ⌘C to the (usually empty) search
        // field; only yield to native copy-selection when there IS a selection.
        if ctx.isCommandPressed, ctx.characters == "c" {
            if ctx.isEditingText, ctx.hasTextSelection { return .passThrough }
            return ctx.hasSelection ? .copySelection : .passThrough
        }

        if ctx.isDetailPresented {
            // While editing a tag (or any focused field) in detail mode, editing
            // keys must reach the field editor — otherwise adding a tag or
            // selecting preview text is impossible.
            if ctx.isEditingText { return .passThrough }
            if ctx.isCommandPressed, ctx.characters == "k" { return .openPalette }

            if (ctx.keyCode == leftArrow && ctx.isCommandPressed) || ctx.keyCode == escape {
                return .closeDetail
            }
            if isReturn && ctx.isCommandPressed { return .stageSelection }
            if isReturn {
                guard !ctx.isComposingText else { return .passThrough }
                return .pasteSelection
            }
            // Everything else (↑↓ scrolling the detail pane) belongs to the view
            return .passThrough
        }

        // LIST mode
        if ctx.isCommandPressed, ctx.characters == "k" { return .openPalette }

        if ctx.isCommandPressed, isReturn {
            guard !ctx.isComposingText, ctx.hasSelection else { return .passThrough }
            return .stageSelection
        }

        // ⌘→ opens detail. Plain → belongs to the search field's caret.
        if ctx.keyCode == rightArrow {
            guard ctx.isCommandPressed, !ctx.isComposingText, ctx.hasSelection else {
                return .passThrough
            }
            return .openDetail
        }

        // ⌘1–9 pastes the Nth visible row
        if ctx.isCommandPressed, let characters = ctx.characters, let n = Int(characters),
           n >= 1, n <= 9, n - 1 < ctx.visibleItemCount {
            return .pasteRow(index: n - 1)
        }

        switch ctx.keyCode {
        case upArrow:
            return ctx.isComposingText ? .passThrough : .moveSelection(by: -1)
        case downArrow:
            return ctx.isComposingText ? .passThrough : .moveSelection(by: 1)
        case returnKey, keypadEnter:
            guard !ctx.isComposingText else { return .passThrough }
            return .pasteSelection
        case escape:
            // Esc clears the query first, and only then closes the overlay
            guard !ctx.isComposingText else { return .passThrough }
            return ctx.isSearchTextEmpty ? .closeOverlay : .clearSearch
        case tab:
            return ctx.isComposingText ? .passThrough : .switchTab
        case space:
            // Space always belongs to text input / IME
            return .passThrough
        default:
            // All other keys (typing) fall through to the focused field
            return .passThrough
        }
    }
}
