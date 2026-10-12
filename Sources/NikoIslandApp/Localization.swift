import Foundation

/// Every user-facing string goes through `L`. Keys are the English text; the
/// zh-Hans table is compiled from `Assets/Localizable.xcstrings` by
/// `scripts/make-app.sh`. Outside a bundle (e.g. `swift run`) the key is shown as is.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
