import AppKit
import Foundation
import Observation

/// Single source of truth for what the notch shows. Owns timing (hover delay, close delay, popup
/// duration); the decision rules live in `NotchTransition`.
@Observable
final class NotchViewModel {
    private(set) var state: NotchState = .closed
    /// Popup shown inside the expanded surface instead of growing it again.
    private(set) var banner: NotchEvent?
    private(set) var isHovering = false
    private(set) var hasLiveContent = false

    /// Time the cursor must rest on the surface before it expands.
    var hoverDelay: TimeInterval = 0.15
    /// Longest the expanded surface lingers once the cursor has left it for the surrounding grace
    /// zone; coming back in time keeps it open. Leaving the zone closes it at once.
    var closeDelay: TimeInterval = 0.8
    /// How often the cursor is checked while it lingers in the grace zone.
    static let graceCheckInterval: Duration = .milliseconds(40)
    /// Screen zone around the expanded surface where the cursor still counts as on it. Set by the
    /// window layer; `nil` means only the drawn shape counts.
    var graceRect: CGRect?
    /// Where the cursor is, in screen coordinates. Injectable so tests can steer it.
    var cursorLocation: () -> CGPoint = { NSEvent.mouseLocation }
    var animation = Anim.Settings.default
    var hapticsEnabled = true
    /// Module shown when hover expands from closed or compact. Phase 2 lets ModuleManager decide.
    var defaultModuleID = "debug"

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var popupTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    // MARK: Inputs

    func hoverChanged(_ inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        hoverTask?.cancel()

        if inside {
            guard let target = NotchTransition.stateOnHoverExpand(from: state, defaultModuleID: defaultModuleID) else {
                return
            }
            hoverTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(hoverDelay))
                guard !Task.isCancelled, isHovering else { return }
                setExpanded(target)
            }
        } else {
            hoverTask = Task { [weak self] in
                guard let self else { return }
                // Inside the grace zone the surface lingers until the deadline; beyond it, it closes now.
                let deadline = ContinuousClock.now + .seconds(closeDelay)
                while isCursorInGraceZone, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: Self.graceCheckInterval)
                    guard !Task.isCancelled, !isHovering else { return }
                }
                if let target = NotchTransition.stateOnHoverExit(from: state, hasLiveContent: hasLiveContent) {
                    banner = nil
                    state = target
                }
            }
        }
    }

    /// Whether the cursor is still near the expanded surface. Without a zone (Debug Preview, tests)
    /// there is no way to tell, so the grace period runs in full.
    private var isCursorInGraceZone: Bool {
        guard state.isExpanded else { return false }
        guard let graceRect else { return true }
        return graceRect.contains(cursorLocation())
    }

    /// Modules report whether they have something worth showing beside the housing.
    func setLiveContent(_ live: Bool) {
        hasLiveContent = live
        if state.isResting {
            state = NotchTransition.restingState(hasLiveContent: live)
        }
    }

    func expand(moduleID: String? = nil) {
        setExpanded(.expanded(moduleID: moduleID ?? defaultModuleID))
    }

    /// Click outside, Escape, or a module asking to go back to rest.
    func collapse() {
        guard !state.isResting else { return }
        popupTask?.cancel()
        bannerTask?.cancel()
        banner = nil
        state = NotchTransition.restingState(hasLiveContent: hasLiveContent)
    }

    func showPopup(_ event: NotchEvent) {
        let resolution = NotchTransition.applyPopup(event, to: state)
        if let bannerEvent = resolution.banner {
            banner = bannerEvent
            bannerTask?.cancel()
            bannerTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(event.duration))
                guard !Task.isCancelled, banner?.id == event.id else { return }
                banner = nil
            }
            return
        }

        popupTask?.cancel()
        state = resolution.state
        popupTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(event.duration))
            guard !Task.isCancelled, case .popup(let current) = state, current.id == event.id else { return }
            state = NotchTransition.restingState(hasLiveContent: hasLiveContent)
        }
    }

    /// Debug Preview override. Popups go through `showPopup` so they keep their timing.
    func override(_ newState: NotchState) {
        hoverTask?.cancel()
        popupTask?.cancel()
        bannerTask?.cancel()
        banner = nil
        switch newState {
        case .popup(let event):
            state = NotchTransition.restingState(hasLiveContent: hasLiveContent)
            showPopup(event)
        case .compact:
            setLiveContent(true)
            state = .compact
        case .closed:
            setLiveContent(false)
            state = .closed
        case .expanded:
            state = newState
        }
    }

    // MARK: Private

    private func setExpanded(_ target: NotchState) {
        popupTask?.cancel()
        if !state.isExpanded {
            performHaptic()
        }
        state = target
    }

    private func performHaptic() {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}
