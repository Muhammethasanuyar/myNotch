import XCTest
@testable import MyNotch

final class PomodoroRulesTests: XCTestCase {
    private let config = PomodoroConfig(workMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, longBreakEvery: 4, autoStart: false, soundEnabled: true)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDurationsComeFromTheConfig() {
        XCTAssertEqual(PomodoroRules.duration(of: .work, config: config), 25 * 60)
        XCTAssertEqual(PomodoroRules.duration(of: .shortBreak, config: config), 5 * 60)
        XCTAssertEqual(PomodoroRules.duration(of: .longBreak, config: config), 15 * 60)
        XCTAssertEqual(PomodoroRules.duration(of: .idle, config: config), 0)
    }

    func testEveryFourthWorkEarnsTheLongBreak() {
        XCTAssertEqual(PomodoroRules.nextPhase(after: .work, completed: 1, config: config), .shortBreak)
        XCTAssertEqual(PomodoroRules.nextPhase(after: .work, completed: 4, config: config), .longBreak)
        XCTAssertEqual(PomodoroRules.nextPhase(after: .work, completed: 8, config: config), .longBreak)
        XCTAssertEqual(PomodoroRules.nextPhase(after: .shortBreak, completed: 1, config: config), .work)
        XCTAssertEqual(PomodoroRules.nextPhase(after: .longBreak, completed: 4, config: config), .work)
        XCTAssertEqual(PomodoroRules.nextPhase(after: .idle, completed: 0, config: config), .work)
    }

    func testFormatting() {
        XCTAssertEqual(PomodoroRules.format(754), "12:34")
        XCTAssertEqual(PomodoroRules.format(0), "00:00")
        XCTAssertEqual(PomodoroRules.format(-5), "00:00")
        XCTAssertEqual(PomodoroRules.format(90 * 60), "90:00")
        XCTAssertEqual(PomodoroRules.format(59.2), "01:00", "rounds up so the display never shows a second the timer has not used")
        XCTAssertEqual(PomodoroRules.minutesText(754), "13")
        XCTAssertEqual(PomodoroRules.minutesText(20), "1")
        XCTAssertEqual(PomodoroRules.minutesText(0), "0")
    }

    func testRemainingAndFraction() {
        XCTAssertEqual(PomodoroRules.remaining(endDate: now.addingTimeInterval(120), now: now), 120)
        XCTAssertEqual(PomodoroRules.remaining(endDate: now.addingTimeInterval(-9), now: now), 0)
        XCTAssertEqual(PomodoroRules.fractionRemaining(remaining: 300, total: 1500), 0.2)
        XCTAssertEqual(PomodoroRules.fractionRemaining(remaining: 9, total: 0), 0)
        let paused = PomodoroSnapshot(phase: .work, endDate: nil, pausedRemaining: 600, completedWorkCount: 0)
        XCTAssertEqual(PomodoroRules.remaining(paused, config: config, now: now), 600)
        XCTAssertEqual(PomodoroRules.remaining(PomodoroSnapshot(), config: config, now: now), 25 * 60, "idle shows the length of the first block")
    }

    func testAdvanceWaitsForATapUnlessAutoStart() {
        let running = PomodoroSnapshot(phase: .work, endDate: now, pausedRemaining: nil, completedWorkCount: 3)
        let waiting = PomodoroRules.advance(running, config: config, now: now)
        XCTAssertEqual(waiting.phase, .longBreak, "the fourth block earns the long break")
        XCTAssertEqual(waiting.completedWorkCount, 4)
        XCTAssertNil(waiting.endDate)
        XCTAssertEqual(waiting.pausedRemaining, 15 * 60)

        var auto = config
        auto.autoStart = true
        let started = PomodoroRules.advance(running, config: auto, now: now)
        XCTAssertEqual(started.endDate, now.addingTimeInterval(15 * 60))
        XCTAssertNil(started.pausedRemaining)
    }

    func testRestoreSettlesAPhaseThatEndedWhileClosed() {
        let ended = PomodoroSnapshot(phase: .work, endDate: now.addingTimeInterval(-3600), pausedRemaining: nil, completedWorkCount: 0)
        let restored = PomodoroRules.restore(ended, config: config, now: now)
        XCTAssertEqual(restored.ended, .work)
        XCTAssertEqual(restored.snapshot.phase, .shortBreak)
        XCTAssertEqual(restored.snapshot.completedWorkCount, 1)
        XCTAssertEqual(restored.snapshot.pausedRemaining, 5 * 60, "waits for a tap; the break did not run unwatched")

        var auto = config
        auto.autoStart = true
        let autoRestored = PomodoroRules.restore(ended, config: auto, now: now)
        XCTAssertEqual(autoRestored.snapshot.endDate, now.addingTimeInterval(5 * 60), "auto-start begins the break now, not an hour ago")

        let stillRunning = PomodoroSnapshot(phase: .work, endDate: now.addingTimeInterval(300), pausedRemaining: nil, completedWorkCount: 0)
        XCTAssertNil(PomodoroRules.restore(stillRunning, config: config, now: now).ended)
        let paused = PomodoroSnapshot(phase: .work, endDate: nil, pausedRemaining: 100, completedWorkCount: 2)
        XCTAssertEqual(PomodoroRules.restore(paused, config: config, now: now).snapshot, paused)
    }

    func testActivityFollowsTheCycle() {
        XCTAssertEqual(PomodoroRules.activity(PomodoroSnapshot()), .idle)
        XCTAssertEqual(PomodoroRules.activity(PomodoroSnapshot(phase: .work, endDate: now, pausedRemaining: nil, completedWorkCount: 0)), .live)
        XCTAssertEqual(PomodoroRules.activity(PomodoroSnapshot(phase: .shortBreak, endDate: nil, pausedRemaining: 300, completedWorkCount: 1)), .live, "waiting for a tap is still mid-cycle")
    }

    func testEventsAndTextInTheSourceLanguage() {
        let bundle = Bundle(for: PomodoroRulesTests.self)
        let workDone = PomodoroRules.phaseEndEvent(ended: .work, next: .shortBreak, config: config, moduleID: "pomodoro", bundle: bundle)
        XCTAssertEqual(workDone.title, "Focus done")
        XCTAssertEqual(workDone.detail, "Take 5 minutes")
        let breakOver = PomodoroRules.phaseEndEvent(ended: .longBreak, next: .work, config: config, moduleID: "pomodoro", bundle: bundle)
        XCTAssertEqual(breakOver.title, "Break over")
        XCTAssertEqual(breakOver.detail, "25 minutes of focus")
        XCTAssertEqual(PomodoroRules.title(for: .longBreak, bundle: bundle), "Long break")
        XCTAssertEqual(PomodoroRules.cycleExplanation(completed: 1, config: config, bundle: bundle), "1 focus block done. Every 4 the break is 15 minutes instead of 5.")
    }

    func testStateStoreRoundTripsAndForgetsIdle() {
        let suite = "PomodoroRulesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = PomodoroStateStore(defaults: defaults)
        let snapshot = PomodoroSnapshot(phase: .shortBreak, endDate: now, pausedRemaining: nil, completedWorkCount: 2)
        store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
        store.save(PomodoroSnapshot())
        XCTAssertNil(store.load(), "an idle cycle leaves nothing behind")
    }

    func testConfigClamping() {
        let clamped = SettingsRules.pomodoroConfig(work: 500, breakMinutes: 0, longBreak: 1, every: 99)
        XCTAssertEqual(clamped.workMinutes, 90)
        XCTAssertEqual(clamped.breakMinutes, 1)
        XCTAssertEqual(clamped.longBreakMinutes, 5)
        XCTAssertEqual(clamped.longBreakEvery, 8)
        let shipped = SettingsRules.pomodoroConfig(work: 25, breakMinutes: 5, longBreak: 15, every: 4)
        XCTAssertEqual(shipped, PomodoroConfig())
    }
}
