import Foundation

/// Pure decisions of the timer: lengths, what comes next, what a snapshot means after a relaunch.
nonisolated enum PomodoroRules {
    static func duration(of phase: PomodoroPhase, config: PomodoroConfig) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .work: return TimeInterval(config.workMinutes) * 60
        case .shortBreak: return TimeInterval(config.breakMinutes) * 60
        case .longBreak: return TimeInterval(config.longBreakMinutes) * 60
        }
    }

    /// After a work phase, a break — the long one every `longBreakEvery` finished works; after a
    /// break, work again. `completed` counts the work phase that just ended.
    static func nextPhase(after phase: PomodoroPhase, completed: Int, config: PomodoroConfig) -> PomodoroPhase {
        switch phase {
        case .idle, .shortBreak, .longBreak:
            return .work
        case .work:
            let every = max(1, config.longBreakEvery)
            return completed > 0 && completed % every == 0 ? .longBreak : .shortBreak
        }
    }

    static func remaining(endDate: Date, now: Date) -> TimeInterval {
        max(0, endDate.timeIntervalSince(now))
    }

    /// Seconds left in whatever state the snapshot is in.
    static func remaining(_ snapshot: PomodoroSnapshot, config: PomodoroConfig, now: Date) -> TimeInterval {
        if let endDate = snapshot.endDate { return remaining(endDate: endDate, now: now) }
        if let paused = snapshot.pausedRemaining { return paused }
        return duration(of: snapshot.phase == .idle ? .work : snapshot.phase, config: config)
    }

    /// 1 with the whole phase ahead, 0 when it is over.
    static func fractionRemaining(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining / total))
    }

    /// "12:34"; never negative, hours roll into the minutes ("90:00").
    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.up))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }

    /// Minutes for the compact wing: rounded up so the last second still reads "1", never "0".
    static func minutesText(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.up))
        return "\(max(minutes, seconds > 0 ? 1 : 0))"
    }

    /// The phase after `phase` finished, applied to the snapshot: counts the work, and either
    /// starts the next phase (auto-start) or leaves it ready with its full length.
    static func advance(_ snapshot: PomodoroSnapshot, config: PomodoroConfig, now: Date) -> PomodoroSnapshot {
        var next = snapshot
        if snapshot.phase == .work { next.completedWorkCount += 1 }
        let phase = nextPhase(after: snapshot.phase, completed: next.completedWorkCount, config: config)
        next.phase = phase
        let length = duration(of: phase, config: config)
        if config.autoStart {
            next.endDate = now.addingTimeInterval(length)
            next.pausedRemaining = nil
        } else {
            next.endDate = nil
            next.pausedRemaining = length
        }
        return next
    }

    /// A snapshot read back at launch: a phase that ended while the app was closed is settled
    /// once (the caller announces it), never re-run.
    static func restore(_ snapshot: PomodoroSnapshot, config: PomodoroConfig, now: Date) -> (snapshot: PomodoroSnapshot, ended: PomodoroPhase?) {
        guard let endDate = snapshot.endDate, endDate <= now else { return (snapshot, nil) }
        var settled = advance(snapshot, config: config, now: now)
        if settled.isRunning {
            // Auto-start: do not pretend the next phase ran while nobody was here; it starts now.
            settled.endDate = now.addingTimeInterval(duration(of: settled.phase, config: config))
        }
        return (settled, snapshot.phase)
    }

    /// Live while a cycle is under way, in any of its states; idle only after a reset.
    static func activity(_ snapshot: PomodoroSnapshot) -> ModuleActivity {
        snapshot.phase == .idle ? .idle : .live
    }

    // MARK: Text

    static func title(for phase: PomodoroPhase, bundle: Bundle = .main) -> String {
        switch phase {
        case .idle: return String(localized: "pomodoro.phase.idle", defaultValue: "Ready to focus", bundle: bundle)
        case .work: return String(localized: "pomodoro.phase.work", defaultValue: "Focus", bundle: bundle)
        case .shortBreak: return String(localized: "pomodoro.phase.shortBreak", defaultValue: "Short break", bundle: bundle)
        case .longBreak: return String(localized: "pomodoro.phase.longBreak", defaultValue: "Long break", bundle: bundle)
        }
    }

    /// The popup when a phase ends: what finished and what comes next.
    static func phaseEndEvent(ended: PomodoroPhase, next: PomodoroPhase, config: PomodoroConfig, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        let minutes = Int(duration(of: next, config: config) / 60)
        switch ended {
        case .work:
            return NotchEvent(
                moduleID: moduleID,
                title: String(localized: "pomodoro.event.workDone", defaultValue: "Focus done", bundle: bundle),
                detail: String(localized: "pomodoro.event.breakNext", defaultValue: "Take \(minutes) minutes", bundle: bundle),
                symbolName: "cup.and.saucer.fill",
                duration: 4
            )
        default:
            return NotchEvent(
                moduleID: moduleID,
                title: String(localized: "pomodoro.event.breakOver", defaultValue: "Break over", bundle: bundle),
                detail: String(localized: "pomodoro.event.workNext", defaultValue: "\(minutes) minutes of focus", bundle: bundle),
                symbolName: "timer",
                duration: 4
            )
        }
    }

    static func cycleExplanation(completed: Int, config: PomodoroConfig, bundle: Bundle = .main) -> String {
        String(localized: "pomodoro.explain.cycle",
               defaultValue: "\(completed) focus \(completed == 1 ? "block" : "blocks") done. Every \(config.longBreakEvery) the break is \(config.longBreakMinutes) minutes instead of \(config.breakMinutes).",
               bundle: bundle)
    }

    static func ringExplanation(_ snapshot: PomodoroSnapshot, config: PomodoroConfig, bundle: Bundle = .main) -> String {
        if snapshot.isRunning {
            return String(localized: "pomodoro.explain.running", defaultValue: "The ring empties as the phase runs out; it moves on its own, nothing to watch.", bundle: bundle)
        }
        if snapshot.isPaused {
            return String(localized: "pomodoro.explain.paused", defaultValue: "Paused. Start continues from here; Reset throws the cycle away.", bundle: bundle)
        }
        return String(localized: "pomodoro.explain.idle", defaultValue: "\(config.workMinutes) minutes of focus, then a \(config.breakMinutes)-minute break. Start begins the first block.", bundle: bundle)
    }
}
