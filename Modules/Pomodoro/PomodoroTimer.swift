import AppKit
import Observation

/// The cycle itself: one sleeping task until the phase ends, nothing ticking in between. Survives
/// a relaunch through `PomodoroStateStore` and a lid closing through the wake notification.
@MainActor
@Observable
final class PomodoroTimer {
    private(set) var snapshot = PomodoroSnapshot()
    var config = PomodoroConfig() {
        didSet { if config != oldValue { save() } }
    }

    /// Called when a phase runs out: what ended and what the cycle moved to.
    var onPhaseEnd: ((PomodoroPhase, PomodoroPhase) -> Void)?
    var onChange: (() -> Void)?

    private let store: PomodoroStateStore
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init(store: PomodoroStateStore = PomodoroStateStore()) {
        self.store = store
    }

    var phase: PomodoroPhase { snapshot.phase }
    var isRunning: Bool { snapshot.isRunning }
    var isPaused: Bool { snapshot.isPaused }

    func remaining(now: Date = Date()) -> TimeInterval {
        PomodoroRules.remaining(snapshot, config: config, now: now)
    }

    /// The whole length of the current phase (work while idle), for the ring.
    var phaseLength: TimeInterval {
        PomodoroRules.duration(of: snapshot.phase == .idle ? .work : snapshot.phase, config: config)
    }

    // MARK: Lifecycle

    func start() {
        if let saved = store.load() {
            let restored = PomodoroRules.restore(saved, config: config, now: Date())
            snapshot = restored.snapshot
            if let ended = restored.ended {
                onPhaseEnd?(ended, snapshot.phase)
            }
            save()
        }
        scheduleEnd()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkEnd() }
        }
        onChange?()
    }

    func stop() {
        endTask?.cancel()
        endTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    // MARK: Controls

    /// Begins the first block, resumes a paused phase, or starts the phase that is waiting.
    func startOrResume() {
        let now = Date()
        var next = snapshot
        if next.phase == .idle {
            next.phase = .work
            next.endDate = now.addingTimeInterval(PomodoroRules.duration(of: .work, config: config))
        } else if let paused = next.pausedRemaining {
            next.endDate = now.addingTimeInterval(paused)
        } else {
            return
        }
        next.pausedRemaining = nil
        apply(next)
    }

    func pause() {
        guard let endDate = snapshot.endDate else { return }
        var next = snapshot
        next.pausedRemaining = PomodoroRules.remaining(endDate: endDate, now: Date())
        next.endDate = nil
        apply(next)
    }

    func toggle() {
        isRunning ? pause() : startOrResume()
    }

    /// Ends the current phase now and moves on, announcing it like a natural end.
    func skip() {
        guard snapshot.phase != .idle else { return }
        finishPhase()
    }

    func reset() {
        apply(PomodoroSnapshot())
    }

    // MARK: Internals

    private func apply(_ next: PomodoroSnapshot) {
        snapshot = next
        save()
        scheduleEnd()
        onChange?()
    }

    private func save() {
        store.save(snapshot)
    }

    private func scheduleEnd() {
        endTask?.cancel()
        endTask = nil
        guard let endDate = snapshot.endDate else { return }
        let seconds = PomodoroRules.remaining(endDate: endDate, now: Date())
        endTask = Task { [weak self] in
            // The continuous clock keeps counting through sleep, so a lid opening after the end
            // fires at once rather than serving the remaining minutes again.
            try? await Task.sleep(for: .seconds(seconds), clock: ContinuousClock())
            guard !Task.isCancelled else { return }
            self?.checkEnd()
        }
    }

    private func checkEnd() {
        guard let endDate = snapshot.endDate, endDate <= Date() else {
            scheduleEnd()
            return
        }
        finishPhase()
    }

    private func finishPhase() {
        let ended = snapshot.phase
        let next = PomodoroRules.advance(snapshot, config: config, now: Date())
        apply(next)
        onPhaseEnd?(ended, next.phase)
    }
}
