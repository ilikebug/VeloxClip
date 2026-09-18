import Foundation

/// The one rule for opening a URL that came out of the clipboard: http(s) only.
/// `file://`, `javascript:`, custom schemes etc. would hand untrusted content to
/// NSWorkspace — a copied `file:///…/payload.command` must never get an "Open" button.
enum WebURL {
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func isOpenable(_ string: String?) -> Bool {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: trimmed) else { return false }
        return isOpenable(url)
    }
}
