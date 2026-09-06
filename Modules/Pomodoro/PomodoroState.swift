import Foundation

/// Where the timer is in its cycle. `idle` is no cycle at all.
nonisolated enum PomodoroPhase: String, Codable, Equatable, Sendable {
    case idle
    case work
    case shortBreak
    case longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

/// The user's lengths, in minutes, and how the cycle behaves between phases.
nonisolated struct PomodoroConfig: Equatable, Sendable {
    var workMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15
    /// Every this many finished work phases, the break is the long one.
    var longBreakEvery = 4
    /// Start the next phase the moment one ends, instead of waiting for a tap.
    var autoStart = false
    var soundEnabled = true
}

/// Everything needed to pick the cycle up after a relaunch.
nonisolated struct PomodoroSnapshot: Codable, Equatable, Sendable {
    var phase: PomodoroPhase = .idle
    /// When the running phase ends; `nil` while paused, ready or idle.
    var endDate: Date?
    /// Seconds left while paused or waiting to start; `nil` while running or idle.
    var pausedRemaining: TimeInterval?
    var completedWorkCount = 0

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
}
