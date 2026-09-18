import CoreGraphics

/// Screen Recording (TCC) for the F1/F2 capture flows. Without the permission
/// `screencapture` still "succeeds" but returns the wallpaper only.
///
/// The preflight result is cached per process by macOS — it stays false until
/// relaunch even after the user grants access — so it must never gate the
/// capture itself (the child `screencapture` process is checked fresh). It is
/// only used to show the system prompt once and to word the failure toast.
enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    private nonisolated(unsafe) static var hasPrompted = false

    /// Shows the system prompt if the permission looks missing and we haven't
    /// asked yet. Returns true when the prompt was just put on screen — the
    /// caller must then NOT start a capture: `screencapture -i` takes a
    /// system-wide mouse grab and the user could not click the alert.
    @MainActor
    static func promptIfNeeded() -> Bool {
        guard !isGranted, !hasPrompted else { return false }
        hasPrompted = true
        CGRequestScreenCaptureAccess()
        return true
    }
}
