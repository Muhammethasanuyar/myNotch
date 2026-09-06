import Foundation

/// The catalog lookup every settings string goes through: a stable key, the English default in
/// code, Turkish in `App/Localizable.xcstrings`.
nonisolated func L(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
    String(localized: key, defaultValue: defaultValue)
}
