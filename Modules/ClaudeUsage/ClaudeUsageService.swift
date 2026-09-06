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

    /// Tokens, blocks and pace from the session logs; dollars merged in from ccusage when present.
    private(set) var cost: CCUsageReport?
    /// Whether ccusage is around to price the day; the report itself no longer depends on it.
    private(set) var costState: CCUsageState = .unknown
    private(set) var isCostRefreshing = false

    /// A session log changed within the last `workingWindow`.
    private(set) var isWorking = false
    private(set) var lastActivityAt: Date?
    private(set) var session: SessionTail?
    /// False when no `projects/` directory exists at all: Claude Code has never run here.
    private(set) var hasLogs = true

    var thresholds = UsageThresholds()
    /// Seconds between scheduled polls; the settings window offers a few multiples of the floor.
    var pollInterval: TimeInterval = UsagePolling.interval
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
    @ObservationIgnored private let ledger = UsageLedger()
    @ObservationIgnored private var latestEntries: [UsageEntry] = []
    @ObservationIgnored private var costTable = CostTable.unknown
    @ObservationIgnored private var ledgerTask: Task<Void, Never>?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var roots: [URL] = []
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
        self.roots = roots
        hasLogs = !roots.isEmpty
        watcher.onChange = { [weak self] urls in self?.logsChanged(urls) }
        watcher.start(roots: roots)
        observeSleep()
        readLogs { ledger, now in await ledger.warmStart(roots: roots, now: now) }

        launcher = CCUsageRunner.locate()
        costState = launcher.map(CCUsageState.ready) ?? .notInstalled
        refreshCost()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                // The suspending clock does not run while the Mac sleeps, so a lid opening does
                // not fire a burst of overdue polls into the shared limiter.
                let interval = self?.pollInterval ?? UsagePolling.interval
                try? await Task.sleep(for: .seconds(interval), clock: SuspendingClock())
            }
        }
    }

    func stop() {
        for task in [pollTask, refreshTask, cooldownTask, wakeTask, signInWatchTask, workingTask, costTask, costDebounceTask, ledgerTask, boundaryTask] {
            task?.cancel()
        }
        ledgerTask = nil
        boundaryTask = nil
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

    /// The ccusage path setting changed: look again and, if something turned up, refresh the cost.
    func relocateCCUsage() {
        guard pollTask != nil else { return }
        launcher = CCUsageRunner.locate()
        costState = launcher.map(CCUsageState.ready) ?? .notInstalled
        lastCostRefresh = nil
        refreshCost()
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
            readLogs { [roots] ledger, now in await ledger.resync(roots: roots, now: now) }
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

        readLogs { ledger, now in await ledger.ingest(urls, now: now) }

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

    /// Asks ccusage for today's dollars — the one thing the logs cannot say — and re-prices the report.
    func refreshCost() {
        guard let launcher, !isCostRefreshing else { return }
        isCostRefreshing = true
        lastCostRefresh = Date()
        let configDirectory = configDirectory
        costTask = Task { [weak self] in
            defer { self?.isCostRefreshing = false }
            do {
                let day = try await CCUsageRunner.daily(using: launcher, configDirectory: configDirectory)
                guard let self, !Task.isCancelled else { return }
                costTable = day.map { CostTable(day: $0, asOf: Date()) } ?? CostTable(day: CCUsageDay(date: ""), asOf: Date())
                costState = .ready(launcher)
            } catch {
                guard let self else { return }
                costState = .failed(String(describing: error))
                Self.log.error("ccusage failed: \(String(describing: error), privacy: .public)")
            }
            self?.rebuildReport()
        }
    }

    // MARK: Native report

    /// Runs one ledger pass off the main actor and rebuilds the report from what it returns.
    private func readLogs(_ pass: @escaping @Sendable (UsageLedger, Date) async -> LedgerSnapshot) {
        let ledger = self.ledger
        let previous = ledgerTask
        ledgerTask = Task { [weak self] in
            // Passes are serialised by the actor; waiting keeps their results in order too.
            _ = await previous?.value
            let started = ContinuousClock.now
            let snapshot = await pass(ledger, Date())
            guard let self, !Task.isCancelled else { return }
            if UserDefaults.standard.bool(forKey: "debugUsageDump") {
                let elapsed = ContinuousClock.now - started
                Self.log.info("ledger pass: \(snapshot.entries.count) entries, \(snapshot.bytesRead) bytes read so far, anchored \(snapshot.isAnchored), \(String(describing: elapsed), privacy: .public)")
            }
            if !snapshot.isAnchored {
                Self.log.info("block chain is not anchored; the first block may start later than ccusage says")
            }
            latestEntries = snapshot.entries
            if let tail = snapshot.tail { session = tail }
            rebuildReport()
        }
    }

    /// Today's report from the entries on hand and whatever dollars ccusage last reported.
    private func rebuildReport() {
        let now = Date()
        let report = UsageAggregator.report(entries: latestEntries, now: now, cost: costTable)
        cost = report
        if UserDefaults.standard.bool(forKey: "debugUsageDump") {
            let blocks = report.todayBlocks.map { "\($0.id) \($0.totalTokens)\($0.isActive ? "*" : "")" }.joined(separator: ", ")
            Self.log.info("usage today: \(report.today?.totalTokens ?? 0) tokens, $\(report.today?.totalCost ?? 0) (\(String(describing: report.costSource), privacy: .public)); blocks: \(blocks, privacy: .public)")
        }
        scheduleBoundary(after: report, now: now)
        onDataChanged?()
    }

    /// The report changes on its own when the running block's window closes or the day rolls over.
    private func scheduleBoundary(after report: CCUsageReport, now: Date) {
        boundaryTask?.cancel()
        var next = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        if let end = report.activeBlock?.endTime, end > now { next = min(next, end) }
        let delay = min(max(1, next.timeIntervalSince(now) + 1), 15 * 60)
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), clock: SuspendingClock())
            guard !Task.isCancelled else { return }
            self?.rebuildReport()
        }
    }
}
