import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var resourceName: String? {
        switch self {
        case .system:
            return Self.resolvedSystemLanguage.resourceName
        case .zhHans:
            return "zh-hans"
        case .en:
            return "en"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    static var resolvedSystemLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .zhHans : .en
    }

    func displayName(language: AppLanguage = .system) -> String {
        switch self {
        case .system:
            return L10n.string("language.system", language: language)
        case .zhHans:
            return L10n.string("language.zhHans", language: language)
        case .en:
            return L10n.string("language.en", language: language)
        }
    }
}

enum L10n {
    private static let languageLock = NSLock()
    // Access is serialized through languageLock.
    nonisolated(unsafe) private static var cachedLanguage: AppLanguage = .system

    static func string(_ key: String, language: AppLanguage = currentLanguage) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String,
                       _ arguments: CVarArg...,
                       language: AppLanguage = currentLanguage) -> String {
        String(format: string(key, language: language), locale: locale(for: language), arguments: arguments)
    }

    static var currentLanguage: AppLanguage {
        languageLock.withLock { cachedLanguage }
    }

    static func updateCurrentLanguage(_ language: AppLanguage) {
        languageLock.withLock {
            cachedLanguage = language
        }
    }

    static func locale(for language: AppLanguage = currentLanguage) -> Locale {
        if let identifier = language.localeIdentifier {
            return Locale(identifier: identifier)
        }
        return Locale.current
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let resourceName = language.resourceName else {
            return Bundle.module
        }

        if let path = Bundle.main.path(forResource: resourceName, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        if let path = Bundle.module.path(forResource: resourceName, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        return Bundle.module
    }
}
