import ApplicationServices

/// Accessibility (AX) permission, required to inject the synthetic Cmd+V that
/// pastes into the target app. Without it `CGEvent.postToPid` silently does
/// nothing.
///
/// Mirrors `ScreenCapturePermission`: one place owning the subtle policy, which
/// is that the system dialog must be shown at most once per session. Without
/// that guard it reopens on every failed paste and on every app deactivation.
/// This logic used to exist in two byte-identical copies — `PasteStackService`
/// had the once-per-session flag, `WindowManager` did not, so the latter
/// re-prompted every time.
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    private nonisolated(unsafe) static var hasPrompted = false

    /// Shows the system prompt if the permission is missing and we haven't
    /// asked yet. Returns true when the app may inject events.
    @MainActor
    @discardableResult
    static func promptIfNeeded() -> Bool {
        if isGranted { return true }
        guard !hasPrompted else { return false }
        hasPrompted = true
        // kAXTrustedCheckOptionPrompt is a mutable global the Swift 6 checker
        // rejects; its value is the literal below
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }
}
