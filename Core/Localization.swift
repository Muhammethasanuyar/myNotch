import Foundation

/// The catalog lookup user-facing strings go through: a stable key, the English default in code,
/// Turkish in `App/Localizable.xcstrings` (kept in sync by `scripts/sync-settings-strings.py`).
nonisolated func L(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
    String(localized: key, defaultValue: defaultValue)
}
