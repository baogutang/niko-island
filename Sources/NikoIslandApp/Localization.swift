import Foundation

/// Every user-facing string goes through `L`. Keys are the English text; the
/// zh-Hans table is compiled from `Assets/Localizable.xcstrings` by
/// `scripts/make-app.sh`. Outside a bundle (e.g. `swift run`) the key is shown as is.
enum Localization {
    /// Written on the main thread when the language setting changes, read wherever a string is drawn.
    nonisolated(unsafe) private static var bundle = Bundle.main

    /// "system" follows macOS; "en" and "zh-Hans" pin the app to one language.
    static func use(language: String) {
        if language != "system", let path = Bundle.main.path(forResource: language, ofType: "lproj"), let pinned = Bundle(path: path) {
            bundle = pinned
        } else {
            bundle = .main
        }
    }

    /// Dates are written in the language the strings are in, keeping the user's
    /// own region and clock settings. Without this a pinned language (or a Mac
    /// whose language and region differ) mixes two languages in one sentence.
    static var locale: Locale {
        let language = bundle.preferredLocalizations.first ?? "en"
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        return Locale(components: components)
    }

    /// "A, B and C" in the language the strings are in.
    static func list(_ items: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

func L(_ key: String) -> String {
    Localization.string(key)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
