import Foundation

/// Developer launch arguments, passed as `MyNotch.app --args -debugTintNotch YES -openDebugPreview YES`.
/// `UserDefaults` exposes `-key value` pairs from the argument domain automatically.
nonisolated struct LaunchOptions: Equatable, Sendable {
    /// Paints the panel footprint and notch rectangle so alignment can be checked on screen.
    let debugTintNotch: Bool
    /// Opens the Debug Preview window right after launch.
    let openDebugPreview: Bool

    static func read(from defaults: UserDefaults) -> LaunchOptions {
        LaunchOptions(
            debugTintNotch: defaults.bool(forKey: Key.debugTintNotch),
            openDebugPreview: defaults.bool(forKey: Key.openDebugPreview)
        )
    }

    private enum Key {
        static let debugTintNotch = "debugTintNotch"
        static let openDebugPreview = "openDebugPreview"
    }
}
