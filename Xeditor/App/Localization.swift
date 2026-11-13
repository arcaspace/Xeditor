import AppKit

/// UI languages offered in Preferences. English is the default and also the
/// source language: every lookup key is the English string itself.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"

    /// Name shown in the language popup, written in that language.
    var nativeName: String {
        switch self {
        case .english:            return "English"
        case .simplifiedChinese:  return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese:           return "日本語"
        case .korean:             return "한국어"
        }
    }
}

/// Runtime language switching. The selected language is stored in user
/// defaults and applies immediately; English strings double as the keys, so a
/// missing translation gracefully falls back to English.
final class Localization {
    static let shared = Localization()
    static let didChangeNotification = Notification.Name("XeditorLocalizationDidChange")

    private static let defaultsKey = "app.language"
    private let defaults = UserDefaults.standard

    private init() {}

    var language: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: Self.defaultsKey),
                  let value = AppLanguage(rawValue: raw) else {
                return .english
            }
            return value
        }
        set {
            guard newValue != language else { return }
            defaults.set(newValue.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    func translate(_ key: String) -> String {
        switch language {
        case .english:            return key
        case .simplifiedChinese:  return LocalizationStrings.zhHans[key] ?? key
        case .traditionalChinese: return LocalizationStrings.zhHant[key] ?? key
        case .japanese:           return LocalizationStrings.ja[key] ?? key
        case .korean:             return LocalizationStrings.ko[key] ?? key
        }
    }
}

/// Localized string for an English source string.
func L(_ key: String) -> String {
    Localization.shared.translate(key)
}

/// Localized string with `String(format:)` arguments.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localization.shared.translate(key), arguments: args)
}

/// Picks the singular or plural variant and localizes it.
func LP(_ count: Int, _ singular: String, _ plural: String) -> String {
    L(count == 1 ? singular : plural)
}
