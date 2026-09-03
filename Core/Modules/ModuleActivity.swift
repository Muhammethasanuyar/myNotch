import Foundation

/// How much of the notch a module currently deserves.
///
/// The order matters: `ModuleResolver` picks the highest activity first, and only then the
/// highest priority among equals.
nonisolated enum ModuleActivity: Int, Comparable, CaseIterable, Sendable {
    /// Nothing to show; the module stays out of the notch.
    case idle
    /// Worth a permanent place in the compact state.
    case live
    /// Needs to interrupt with a popup.
    case urgent

    static func < (lhs: ModuleActivity, rhs: ModuleActivity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
