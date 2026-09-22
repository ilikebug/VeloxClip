import Foundation

/// Decides whose copies never reach history.
///
/// Shipped as four hardcoded bundle IDs with no UI, so anyone using a password
/// manager other than 1Password / Keychain / Apple Passwords had their secrets
/// recorded. The defaults remain, but the user can now add their own and remove
/// any default they disagree with.
@MainActor
final class BlacklistManager {
    static let shared = BlacklistManager()

    /// Known secret-holding apps, ignored unless the user removes them.
    nonisolated static let defaultBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    private var userAdded: Set<String>
    private var userRemoved: Set<String>
    /// The additions as the user's system reported them, for display.
    private var userAddedOriginal: [String]

    /// Bundle IDs are case-insensitive on macOS; compare in one case so the
    /// blacklist cannot be bypassed by capitalisation.
    private nonisolated static func normalize(_ id: String) -> String { id.lowercased() }

    private nonisolated static let normalizedDefaults = Set(defaultBundleIDs.map { $0.lowercased() })

    init(userAdded: [String] = [], userRemoved: [String] = []) {
        self.userAdded = Set(userAdded.map(Self.normalize))
        self.userRemoved = Set(userRemoved.map(Self.normalize))
        self.userAddedOriginal = userAdded
    }

    /// Re-reads the user's edits. Called when settings load or change.
    func apply(userAdded: [String], userRemoved: [String]) {
        self.userAdded = Set(userAdded.map(Self.normalize))
        self.userRemoved = Set(userRemoved.map(Self.normalize))
        self.userAddedOriginal = userAdded
    }

    /// Defaults plus the user's additions, minus anything the user removed.
    /// Removal wins, so one pair of lists expresses both directions.
    ///
    /// Returns the ids in their ORIGINAL casing — this list is shown in
    /// Settings, and `com.apple.Passwords` rendered as `com.apple.passwords`
    /// looks wrong in the one screen whose job is to let the user verify what
    /// is blocked. Matching stays case-insensitive.
    var blockedBundleIDs: [String] {
        var byNormalized: [String: String] = [:]
        for id in Self.defaultBundleIDs {
            byNormalized[Self.normalize(id)] = id
        }
        for id in userAddedOriginal {
            byNormalized[Self.normalize(id)] = id
        }
        for normalized in userRemoved {
            byNormalized.removeValue(forKey: normalized)
        }
        return byNormalized.values.sorted { $0.lowercased() < $1.lowercased() }
    }

    func shouldIgnore(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        let normalized = Self.normalize(bundleID)
        guard !userRemoved.contains(normalized) else { return false }
        return userAdded.contains(normalized) || Self.normalizedDefaults.contains(normalized)
    }
}
