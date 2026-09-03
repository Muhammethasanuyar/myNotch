import Foundation

/// Pure transition rules of the notch state machine. No timing lives here; `NotchViewModel`
/// schedules delays and applies these decisions.
nonisolated enum NotchTransition {
    /// Outcome of an incoming popup: either the surface changes state, or the popup is shown
    /// as a banner inside the already-expanded surface.
    struct PopupResolution: Equatable, Sendable {
        let state: NotchState
        let banner: NotchEvent?
    }

    /// Where the notch rests when nobody interacts with it.
    static func restingState(hasLiveContent: Bool) -> NotchState {
        hasLiveContent ? .compact : .closed
    }

    /// A popup interrupts closed, compact and other popups. While expanded it must not grow the
    /// surface a second time, so it becomes a banner instead.
    static func applyPopup(_ event: NotchEvent, to current: NotchState) -> PopupResolution {
        switch current {
        case .expanded:
            return PopupResolution(state: current, banner: event)
        case .closed, .compact, .popup:
            return PopupResolution(state: .popup(event), banner: nil)
        }
    }

    /// The state to expand into once the hover delay has elapsed, or `nil` when already expanded.
    static func stateOnHoverExpand(from current: NotchState, defaultModuleID: String) -> NotchState? {
        switch current {
        case .expanded:
            return nil
        case .popup(let event):
            return .expanded(moduleID: event.moduleID)
        case .closed, .compact:
            return .expanded(moduleID: defaultModuleID)
        }
    }

    /// The state to fall back to once the cursor has left, or `nil` when nothing needs to change.
    static func stateOnHoverExit(from current: NotchState, hasLiveContent: Bool) -> NotchState? {
        current.isExpanded ? restingState(hasLiveContent: hasLiveContent) : nil
    }
}
