import Foundation

/// What the notch surface shows. `NotchViewModel` owns the current value and its timing;
/// `NotchTransition` owns the rules for moving between values.
nonisolated enum NotchState: Equatable, Sendable {
    /// Coincides with the physical housing; invisible on screens without one.
    case closed
    /// Housing plus live content on both sides.
    case compact
    /// Full module UI below the housing.
    case expanded(moduleID: String)
    /// Transient announcement; ends by returning to the resting state.
    case popup(NotchEvent)

    var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    var isPopup: Bool {
        if case .popup = self { return true }
        return false
    }

    /// Closed and compact: the states the notch rests in without user interaction.
    var isResting: Bool {
        self == .closed || self == .compact
    }
}
