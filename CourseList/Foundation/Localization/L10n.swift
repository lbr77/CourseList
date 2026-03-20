import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case enUS = "en-US"
    case zhCN = "zh-CN"

    public static let `default`: AppLanguage = .zhCN

    public var title: String {
        switch self {
        case .enUS:
            return L10n.tr("English (US)")
        case .zhCN:
            return L10n.tr("Simplified Chinese")
        }
    }
}

public extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("CourseList.appLanguageDidChange")
}

public enum L10n {
    private static let tableName = "AppLocalizable"
    private static let languageKey = "app.language"

    public static func currentLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let raw = defaults.string(forKey: languageKey) else {
            return .default
        }
        return AppLanguage(rawValue: raw) ?? .default
    }

    public static func setLanguage(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        guard currentLanguage(defaults: defaults) != language else { return }
        defaults.set(language.rawValue, forKey: languageKey)
        NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
    }

    public static func tr(_ key: String) -> String {
        let bundle = localizationBundle(for: currentLanguage())
        return bundle.localizedString(forKey: key, value: key, table: tableName)
    }

    public static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = tr(key)
        let locale = Locale(identifier: currentLanguage().rawValue)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func localizationBundle(for language: AppLanguage) -> Bundle {
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        let baseCode = language.rawValue.split(separator: "-").first.map(String.init)
        if let baseCode,
           let path = Bundle.main.path(forResource: baseCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        return .main
    }
}
