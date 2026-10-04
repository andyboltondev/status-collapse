import Foundation

/// A language the interface is translated into. `code` is the name of its `.lproj` folder.
struct AppLanguage: Identifiable, Hashable {
    let code: String
    /// The language's own name, so it can be found whichever language is showing.
    let name: String
    var id: String { code }
    var isRightToLeft: Bool { code == "ar" }

    static let system = "system"

    /// British English is the base language; every other string falls back to it.
    static let fallback = "en-GB"

    static let all: [AppLanguage] = [
        ("en-GB", "English (UK)"), ("en-US", "English (US)"),
        ("ar", "العربية"), ("bg", "Български"), ("cs", "Čeština"), ("da", "Dansk"),
        ("de", "Deutsch"), ("el", "Ελληνικά"), ("es", "Español"), ("et", "Eesti"),
        ("fi", "Suomi"), ("fr", "Français"), ("ga", "Gaeilge"), ("hi", "हिन्दी"),
        ("hr", "Hrvatski"), ("hu", "Magyar"), ("id", "Bahasa Indonesia"), ("it", "Italiano"),
        ("ja", "日本語"), ("ko", "한국어"), ("lt", "Lietuvių"), ("lv", "Latviešu"),
        ("mt", "Malti"), ("nb", "Norsk bokmål"), ("nl", "Nederlands"), ("pl", "Polski"),
        ("pt-BR", "Português (Brasil)"), ("pt-PT", "Português (Portugal)"), ("ro", "Română"),
        ("ru", "Русский"), ("sk", "Slovenčina"), ("sl", "Slovenščina"), ("sv", "Svenska"),
        ("tr", "Türkçe"), ("uk", "Українська"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
    ].map { AppLanguage(code: $0.0, name: $0.1) }

    static func named(_ code: String) -> AppLanguage? { all.first { $0.code == code } }

    /// The best translation for the user's preferred languages, in order, or British English.
    static func resolve(preferred: [String] = Locale.preferredLanguages) -> String {
        for identifier in preferred {
            let locale = Locale(identifier: identifier)
            guard let language = locale.language.languageCode?.identifier else { continue }
            let region = locale.language.region?.identifier
            let script = locale.language.script?.identifier
            let code: String
            switch language {
            case "en": code = ["US", "CA", "PH"].contains(region) ? "en-US" : "en-GB"
            case "pt": code = region == nil || region == "BR" ? "pt-BR" : "pt-PT"
            case "zh": code = script == "Hant" || ["TW", "HK", "MO"].contains(region) ? "zh-Hant" : "zh-Hans"
            case "no", "nn", "nb": code = "nb"
            default: code = language
            }
            if named(code) != nil { return code }
        }
        return fallback
    }
}

/// Looks strings up in the chosen language's bundle, so the language can change without
/// relaunching. Keys are the British English text.
@MainActor
enum Strings {
    private static var table: Bundle?
    private static var base: Bundle?
    private(set) static var isRightToLeft = false
    /// The chosen language's locale, for formatting dates in it.
    private(set) static var locale = Locale(identifier: AppLanguage.fallback)

    /// Selects `choice`: an `AppLanguage` code, or `AppLanguage.system` to follow macOS.
    static func use(_ choice: String) {
        let code = choice == AppLanguage.system ? AppLanguage.resolve() : choice
        isRightToLeft = AppLanguage.named(code)?.isRightToLeft ?? false
        locale = Locale(identifier: code)
        table = bundle(for: code)
        base = bundle(for: AppLanguage.fallback)
    }

    private static func bundle(for code: String) -> Bundle? {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    static func string(_ key: String) -> String {
        let missing = "\u{0}missing"
        if let value = table?.localizedString(forKey: key, value: missing, table: nil), value != missing { return value }
        if let value = base?.localizedString(forKey: key, value: missing, table: nil), value != missing { return value }
        return key
    }
}

/// The translated form of `key`, with `args` substituted for any format specifiers.
@MainActor
func L(_ key: String, _ args: CVarArg...) -> String {
    let text = Strings.string(key)
    return args.isEmpty ? text : String(format: text, locale: Locale(identifier: "en"), arguments: args)
}
