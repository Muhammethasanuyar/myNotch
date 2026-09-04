import AppKit
import Foundation
import Observation
import os

// Adapted from https://github.com/ericjypark/codex-island (MIT): five-minute polling with a sticky
// rate-limit cooldown, the post-wake grace period and the credential-store watch while signed out.

/// Everything the Claude module knows: official limits from Anthropic, cost from ccusage, and
/// liveness from the session logs. Polling runs whether or not the notch is open, so hovering
/// never shows stale numbers.
@MainActor
@Observable
final class ClaudeUsageService {
    private(set) var auth: UsageAuthState = .signedOut
    private(set) var snapshot: UsageSnapshot?
    private(set) var subscriptionType: String?
    private(set) var isRefreshing = false
    private(set) var lastPollAt: Date?

    private(set) var cost: CCUsageReport?
    private(set) var costState: CCUsageState = .unknown
    private(set) var isCostRefreshing = false

    /// A session log changed within the last `workingWindow`.
    private(set) var isWorking = false
    private(set) var lastActivityAt: Date?
    private(set) var session: SessionTail?
    /// False when no `projects/` directory exists at all: Claude Code has never run here.
    private(set) var hasLogs = true

    var thresholds = UsageThresholds()
    var onCrossing: ((ThresholdCrossing) -> Void)?
    var onWindowReset: ((UsageWindowKind, UsageWindow) -> Void)?
    var onWorkingChanged: ((Bool) -> Void)?
    var onDataChanged: (() -> Void)?

    static let workingWindow: Duration = .seconds(10)
    /// ccusage re-reads every log on each run, so cost refreshes wait for a pause in the work…
    static let costDebounce: Duration = .seconds(20)
    /// …but never fall further behind than this while the work goes on.
    static let costMaxAge: TimeInterval = 120

    private let urlSession: URLSession
    private let environment: [String: String]
    private let watcher = ProjectsWatcher()
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "claude-usage")

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var signInWatchTask: Task<Void, Never>?
    @ObservationIgnored private var workingTask: Task<Void, Never>?
    @ObservationIgnored private var costTask: Task<Void, Never>?
    @ObservationIgnored private var costDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var thresholdMemory = ThresholdMemory()
    @ObservationIgnored private var cooldownUntil: Date?
    @ObservationIgnored private var launcher: CCUsageLauncher?
    @ObservationIgnored private var lastCostRefresh: Date?
    @ObservationIgnored private var storeFingerprint: Date?

    init(urlSession: URLSession = .shared, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.urlSession = urlSession
        self.environment = environment
    }

    var configDirectory: String? {
        UserDefaults.standard.string(forKey: "claudeConfigDir") ?? environment[ClaudeCredentials.configDirectoryKey]
    }

    var isStale: Bool {
        UsagePolling.isStale(fetchedAt: snapshot?.fetchedAt, now: Date())
    }

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil else { return }
        let roots = ClaudePaths.projectsDirectories(environment: overriddenEnvironment)
        hasLogs = !roots.isEmpty
        watcher.onChange = { [weak self] urls in self?.logsChanged(urls) }
        watcher.start(roots: roots)
        observeSleep()

        launcher = CCUsageRunner.locate()
        costState = launcher.map(CCUsageState.ready) ?? .notInstalled
        refreshCost()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                // The suspending clock does not run while the Mac sleeps, so a lid opening does
                // not fire a burst of overdue polls into the shared limiter.
                try? await Task.sleep(for: .seconds(UsagePolling.interval), clock: SuspendingClock())
            }
        }
    }

    func stop() {
        for task in [pollTask, refreshTask, cooldownTask, wakeTask, signInWatchTask, workingTask, costTask, costDebounceTask] {
            task?.cancel()
        }
        pollTask = nil
        refreshTask = nil
        cooldownTask = nil
        wakeTask = nil
        signInWatchTask = nil
        workingTask = nil
        costTask = nil
        costDebounceTask = nil
        watcher.stop()
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sleepObservers.removeAll()
        isWorking = false
    }

    private var overriddenEnvironment: [String: String] {
        var env = environment
        if let configDirectory { env[ClaudeCredentials.configDirectoryKey] = configDirectory }
        return env
    }

    // MARK: Official usage

    /// User-initiated refresh: ignores the schedule but still respects a rate-limit cooldown.
    func refreshUsage() {
        Task { await pollOnce(force: true) }
    }

    private func pollOnce(force: Bool = false) async {
        let now = Date()
        if let cooldownUntil, now < cooldownUntil { return }
        guard force || UsagePolling.shouldPoll(now: now, lastPoll: lastPollAt, cooldownUntil: cooldownUntil) else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let credential = await ClaudeCredentials.resolve(environment: environment, configDirectory: configDirectory) else {
            apply(auth: .signedOut)
            return
        }
        subscriptionType = credential.subscriptionType
        if credential.isExpired(at: Date()) {
            apply(auth: .tokenExpired)
            return
        }
        lastPollAt = Date()
        let outcome = await UsageFetcher.fetch(token: credential.accessToken, session: urlSession)
        guard !Task.isCancelled else { return }
        apply(outcome)
    }

    private func apply(_ outcome: UsageFetcher.Outcome) {
        let now = Date()
        switch outcome {
        case .usage(let fetched):
            let previous = snapshot
            snapshot = UsageMerge.merge(previous: previous, fetched: fetched, now: now)
            cooldownUntil = nil
            apply(auth: .ok)
            for kind in UsageWindowKind.allCases where UsageMerge.didReset(previous: previous?[kind], current: fetched[kind]) {
                if let window = fetched[kind] { onWindowReset?(kind, window) }
            }
            let evaluation = ThresholdMemory.evaluate(snapshot: fetched, thresholds: thresholds, memory: thresholdMemory)
            thresholdMemory = evaluation.memory
            evaluation.crossings.forEach { onCrossing?($0) }
        case .unauthorized:
            apply(auth: .tokenExpired)
        case .reauthRequired:
            apply(auth: .reauthRequired)
        case .rateLimited:
            let until = now.addingTimeInterval(UsagePolling.rateLimitCooldown)
            cooldownUntil = until
            apply(auth: .rateLimited(until: until))
            scheduleCooldownRetry(at: until)
        case .failed(let message):
            snapshot = UsageMerge.merge(previous: snapshot, fetched: nil, now: now)
            apply(auth: .unreachable(message))
            Self.log.error("usage poll failed: \(message, privacy: .public)")
        }
        onDataChanged?()
    }

    private func apply(auth newAuth: UsageAuthState) {
        auth = newAuth
        if newAuth.awaitsSignIn {
            startSignInWatch()
        } else {
            signInWatchTask?.cancel()
            signInWatchTask = nil
        }
        onDataChanged?()
    }

    /// One retry shortly after the cooldown, or recovery would wait for the next regular tick.
    private func scheduleCooldownRetry(at until: Date) {
        cooldownTask?.cancel()
        cooldownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow + 10))
            guard !Task.isCancelled else { return }
            await self?.pollOnce(force: true)
        }
    }

    /// While signed out, the credential store's metadata is checked every few seconds so a fresh
    /// `claude` login shows up within seconds rather than at the next poll. Metadata only: no
    /// secret is read until something changed.
    private func startSignInWatch() {
        guard signInWatchTask == nil else { return }
        let configDirectory = configDirectory
        signInWatchTask = Task { [weak self] in
            var known = await Task.detached { ClaudeCredentials.storeFingerprint(configDirectory: configDirectory) }.value
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(UsagePolling.signInWatchInterval))
                guard !Task.isCancelled else { return }
                let current = await Task.detached { ClaudeCredentials.storeFingerprint(configDirectory: configDirectory) }.value
                if current != known {
                    known = current
                    await self?.pollOnce(force: true)
                }
            }
        }
    }

    // MARK: Sleep and wake

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTask?.cancel() }
        })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWakeRefresh() }
        })
    }

    private func scheduleWakeRefresh() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(UsagePolling.wakeGrace))
            guard !Task.isCancelled, let self else { return }
            if UsagePolling.shouldRefreshAfterWake(lastPoll: lastPollAt, now: Date()) {
                await pollOnce(force: true)
            }
        }
    }

    // MARK: Session logs

    private func logsChanged(_ urls: [URL]) {
        let now = Date()
        lastActivityAt = now
        if !isWorking {
            isWorking = true
            Self.log.info("claude working (\(urls.count) log(s) changed)")
            onWorkingChanged?(true)
        }
        workingTask?.cancel()
        workingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.workingWindow)
            guard !Task.isCancelled, let self else { return }
            isWorking = false
            Self.log.info("claude idle")
            onWorkingChanged?(false)
        }

        if let newest = urls.last {
            Task { [weak self] in
                let tail = await Task.detached(priority: .utility) {
                    SessionTailParser.readTail(of: newest).map(SessionTailParser.parse)
                }.value
                guard let self, let tail else { return }
                session = tail
                onDataChanged?()
            }
        }

        if let lastCostRefresh, now.timeIntervalSince(lastCostRefresh) > Self.costMaxAge {
            refreshCost()
        } else {
            costDebounceTask?.cancel()
            costDebounceTask = Task { [weak self] in
                try? await Task.sleep(for: Self.costDebounce)
                guard !Task.isCancelled else { return }
                self?.refreshCost()
            }
        }
    }

    // MARK: Cost

    func refreshCost() {
        guard let launcher, !isCostRefreshing else { return }
        isCostRefreshing = true
        lastCostRefresh = Date()
        let configDirectory = configDirectory
        costTask = Task { [weak self] in
            defer { self?.isCostRefreshing = false }
            do {
                let report = try await CCUsageRunner.report(using: launcher, configDirectory: configDirectory)
                guard let self, !Task.isCancelled else { return }
                cost = report
                costState = .ready(launcher)
            } catch {
                guard let self else { return }
                costState = .failed(String(describing: error))
                Self.log.error("ccusage failed: \(String(describing: error), privacy: .public)")
            }
            self?.onDataChanged?()
        }
    }
}
