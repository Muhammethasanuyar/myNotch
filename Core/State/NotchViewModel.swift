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
    /// Grace period after the cursor leaves, so brushing the edge does not flicker.
    var closeDelay: TimeInterval = 0.1
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
                try? await Task.sleep(for: .seconds(closeDelay))
                guard !Task.isCancelled, !isHovering else { return }
                if let target = NotchTransition.stateOnHoverExit(from: state, hasLiveContent: hasLiveContent) {
                    banner = nil
                    state = target
                }
            }
        }
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
