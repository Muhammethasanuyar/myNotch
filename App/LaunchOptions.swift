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
    /// With `-debugState expanded`, which module to open instead of whoever owns the notch.
    let debugModule: String?
    /// Makes the demo module live, for exercising the engine without a real player.
    let demoLive: Bool
    /// Posts a long-lived event from the demo module, so the banner strip another module gets
    /// inside the expanded surface can be inspected.
    let debugBanner: Bool

    static func read(from defaults: UserDefaults) -> LaunchOptions {
        LaunchOptions(
            debugTintNotch: defaults.bool(forKey: Key.debugTintNotch),
            openDebugPreview: defaults.bool(forKey: Key.openDebugPreview),
            hasLiveContent: defaults.bool(forKey: Key.liveContent),
            debugState: defaults.string(forKey: Key.debugState),
            debugModule: defaults.string(forKey: Key.debugModule),
            demoLive: defaults.bool(forKey: Key.demoLive),
            debugBanner: defaults.bool(forKey: Key.debugBanner)
        )
    }

    private enum Key {
        static let debugTintNotch = "debugTintNotch"
        static let openDebugPreview = "openDebugPreview"
        static let liveContent = "liveContent"
        static let debugState = "debugState"
        static let debugModule = "debugModule"
        static let demoLive = "demoLive"
        static let debugBanner = "debugBanner"
    }
}
