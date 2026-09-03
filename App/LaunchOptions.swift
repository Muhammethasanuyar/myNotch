import Foundation

/// Developer launch arguments, passed as `MyNotch.app --args -debugTintNotch YES -debugState expanded`.
/// `UserDefaults` exposes `-key value` pairs from the argument domain automatically.
nonisolated struct LaunchOptions: Equatable, Sendable {
    /// Paints the panel footprint and outlines the surface so alignment can be checked on screen.
    let debugTintNotch: Bool
    /// Opens the Debug Preview window right after launch.
    let openDebugPreview: Bool
    /// Starts with live content, i.e. in the compact state.
    let hasLiveContent: Bool
    /// Forces a state at launch: `closed`, `compact`, `expanded` or `popup`.
    let debugState: String?

    static func read(from defaults: UserDefaults) -> LaunchOptions {
        LaunchOptions(
            debugTintNotch: defaults.bool(forKey: Key.debugTintNotch),
            openDebugPreview: defaults.bool(forKey: Key.openDebugPreview),
            hasLiveContent: defaults.bool(forKey: Key.liveContent),
            debugState: defaults.string(forKey: Key.debugState)
        )
    }

    private enum Key {
        static let debugTintNotch = "debugTintNotch"
        static let openDebugPreview = "openDebugPreview"
        static let liveContent = "liveContent"
        static let debugState = "debugState"
    }
}
