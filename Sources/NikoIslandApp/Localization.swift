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
