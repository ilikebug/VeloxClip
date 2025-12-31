import Foundation

@MainActor
class BlacklistManager {
    static let shared = BlacklistManager()
    
    // Default ignored apps
    private var ignoredBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.apple.Passwords"
    ]
    
    func shouldIgnore(bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return ignoredBundleIDs.contains(bundleID)
    }
}
