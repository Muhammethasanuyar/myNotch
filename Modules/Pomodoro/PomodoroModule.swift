import AppKit
import SwiftUI

/// A focus timer in the notch: a ring that empties beside the housing, the minutes left, a popup
/// (and a chime) when a phase ends, and the controls on the card.
@MainActor
@Observable
final class PomodoroModule: NotchModule {
    let id = "pomodoro"
    let displayName = L("module.pomodoro", "Pomodoro")
    /// Below music: a running block should not take the strip from a song the user just picked.
    let priority = 8

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle

    let timer: PomodoroTimer
    @ObservationIgnored private var context: ModuleContext?

    /// Always offered: the notch is the timer's only control surface.
    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "timer", isAvailable: true)]
    }

    init(timer: PomodoroTimer = PomodoroTimer()) {
        self.timer = timer
    }

    func start(context: ModuleContext) {
        self.context = context
        timer.onChange = { [weak self] in self?.updateActivity() }
        timer.onPhaseEnd = { [weak self] ended, next in self?.announce(ended: ended, next: next) }
        timer.start()
        updateActivity()
    }

    func stop() {
        timer.stop()
        timer.onChange = nil
        timer.onPhaseEnd = nil
        activity = .idle
        context?.activityChanged()
    }

    private func announce(ended: PomodoroPhase, next: PomodoroPhase) {
        context?.post(PomodoroRules.phaseEndEvent(ended: ended, next: next, config: timer.config, moduleID: id))
        if timer.config.soundEnabled {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    private func updateActivity() {
        let next = PomodoroRules.activity(timer.snapshot)
        guard next != activity else { return }
        activity = next
        context?.activityChanged()
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(PomodoroCompactLeading(timer: timer))
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(PomodoroCompactTrailing(timer: timer))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(PomodoroExpandedView(timer: timer))
    }
}
