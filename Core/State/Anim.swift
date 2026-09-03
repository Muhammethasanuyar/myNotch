import SwiftUI

/// The animation vocabulary of the notch. Timing parameters are defined only here.
nonisolated enum Anim {
    /// Tunable morph parameters. The Debug Preview edits a copy of these live.
    struct Settings: Equatable, Sendable {
        var openResponse: Double = 0.42
        var openDamping: Double = 0.72
        var closeResponse: Double = 0.34
        var closeDamping: Double = 0.86

        static let `default` = Settings()
    }

    /// Growing into compact, popup or expanded: a little overshoot reads as "alive".
    static func morphOpen(_ settings: Settings = .default) -> Animation {
        .spring(response: settings.openResponse, dampingFraction: settings.openDamping)
    }

    /// Shrinking back: crisper, no overshoot past the housing.
    static func morphClose(_ settings: Settings = .default) -> Animation {
        .spring(response: settings.closeResponse, dampingFraction: settings.closeDamping)
    }

    /// Popup entrance choreography (scale 0.9 → 1 with a slight bounce).
    static var popIn: Animation {
        .spring(response: 0.30, dampingFraction: 0.60)
    }

    /// Small property changes: hover shadow, tints.
    static var subtle: Animation {
        .easeInOut(duration: 0.18)
    }

    /// Critically damped: for motion that must not overshoot past a screen edge.
    static var retract: Animation {
        .spring(response: 0.40, dampingFraction: 1.0)
    }

    /// Used for every morph when the user asked macOS to reduce motion.
    static var reduceMotionFallback: Animation {
        .easeInOut(duration: 0.15)
    }

    /// Picks the morph for a state change: resting states close crisply, everything else opens with overshoot.
    static func morph(to state: NotchState, settings: Settings, reduceMotion: Bool) -> Animation {
        if reduceMotion { return reduceMotionFallback }
        return state.isResting ? morphClose(settings) : morphOpen(settings)
    }
}
