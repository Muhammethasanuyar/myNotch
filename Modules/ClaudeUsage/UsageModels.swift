import Foundation

// Adapted from https://github.com/ericjypark/codex-island (MIT): the carry-forward rule for failed
// polls and the reset-keyed threshold memory. Rewritten as pure value types.

/// One rate-limit window as Anthropic reports it.
nonisolated struct UsageWindow: Equatable, Sendable {
    /// 0…1 of the window's allowance already used.
    let utilization: Double
    /// When the window rolls over; `nil` when the server did not say.
    let resetsAt: Date?

    func remaining(at now: Date) -> TimeInterval? {
        resetsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Whether the window this reading described is already gone.
    func hasReset(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// How much of a window of `kind` has already passed, 0…1, worked back from its reset time.
    func elapsedFraction(kind: UsageWindowKind, at now: Date) -> Double? {
        guard let remaining = remaining(at: now) else { return nil }
        return min(1, max(0, 1 - remaining / kind.length))
    }
}

/// Which limit a reading or an alert is about.
nonisolated enum UsageWindowKind: String, Sendable, CaseIterable {
    case fiveHour
    case sevenDay

    var title: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .sevenDay: return "Weekly"
        }
    }

    /// Fits inside a ring.
    var badge: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        }
    }

    /// How long the window lasts, so the ring can show how far into it we are.
    var length: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .sevenDay: return 7 * 86_400
        }
    }
}


/// What one successful call to the usage endpoint told us, or what survived from earlier calls.
nonisolated struct UsageSnapshot: Equatable, Sendable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    /// Weekly windows split by model family ("opus", "sonnet") on plans that report them.
    var weeklyByModel: [String: UsageWindow] = [:]
    /// When the newest reading in this snapshot was fetched.
    var fetchedAt: Date

    subscript(kind: UsageWindowKind) -> UsageWindow? {
        switch kind {
        case .fiveHour: return fiveHour
        case .sevenDay: return sevenDay
        }
    }
}

/// Why the rings might be empty, stale or need the user's attention.
nonisolated enum UsageAuthState: Equatable, Sendable {
    case ok
    /// No Claude Code credentials anywhere: sign in with `claude`.
    case signedOut
    /// Credentials exist but the access token has expired and the CLI has not refreshed it yet.
    case tokenExpired
    /// The token lacks a scope the endpoint needs now; only a fresh `claude /login` fixes it.
    case reauthRequired
    /// The account-wide limiter tripped; nothing is asked again before `until`.
    case rateLimited(until: Date)
    /// Network or server trouble; the last good reading stands.
    case unreachable(String)

    /// States a new token from the CLI would fix, so the credential store is worth watching.
    var awaitsSignIn: Bool {
        switch self {
        case .signedOut, .tokenExpired, .reauthRequired: return true
        case .ok, .rateLimited, .unreachable: return false
        }
    }
}

nonisolated enum UsageMerge {
    /// Keeps the last real reading through a failed poll, unless the window it described has already
    /// reset, in which case a stale number would describe a window that no longer exists.
    static func carryForward(previous: UsageWindow?, fetched: UsageWindow?, now: Date) -> UsageWindow? {
        if let fetched { return fetched }
        guard let previous, !previous.hasReset(at: now) else { return nil }
        return previous
    }

    /// Merges a poll result into what we had. A failed poll (`fetched == nil`) keeps the old
    /// snapshot minus expired windows; a successful one replaces every window it reported.
    static func merge(previous: UsageSnapshot?, fetched: UsageSnapshot?, now: Date) -> UsageSnapshot? {
        let fiveHour = carryForward(previous: previous?.fiveHour, fetched: fetched?.fiveHour, now: now)
        let sevenDay = carryForward(previous: previous?.sevenDay, fetched: fetched?.sevenDay, now: now)
        var weekly = fetched?.weeklyByModel ?? [:]
        if fetched == nil {
            weekly = (previous?.weeklyByModel ?? [:]).filter { !$0.value.hasReset(at: now) }
        }
        guard fiveHour != nil || sevenDay != nil || !weekly.isEmpty else { return nil }
        return UsageSnapshot(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            weeklyByModel: weekly,
            fetchedAt: fetched?.fetchedAt ?? previous?.fetchedAt ?? now
        )
    }

    /// A window rolled over: its reset time moved forward and the old reading was not trivial.
    static func didReset(previous: UsageWindow?, current: UsageWindow?) -> Bool {
        guard let previous, let current, let before = previous.resetsAt, let after = current.resetsAt else { return false }
        return after > before && previous.utilization >= 0.25 && current.utilization < previous.utilization
    }
}

// MARK: Threshold alerts

nonisolated struct UsageThresholds: Equatable, Sendable {
    var warning: Double = 0.80
    var critical: Double = 0.95

    /// Ascending, and only the sane ones: an inverted pair means "no thresholds".
    var ordered: [Double] {
        guard warning < critical else { return [] }
        return [warning, critical]
    }
}

/// A threshold a window just went over.
nonisolated struct ThresholdCrossing: Equatable, Sendable {
    let kind: UsageWindowKind
    let threshold: Double
    let window: UsageWindow
}

/// Remembers which crossings were announced, keyed by the window's reset time so a rollover
/// forgets them. The first reading only primes the memory: opening the app at 96 % must not
/// produce a retroactive alert.
nonisolated struct ThresholdMemory: Equatable, Sendable {
    struct Key: Hashable, Sendable {
        let kind: UsageWindowKind
        let threshold: Double
        let resetsAt: Date
    }

    private(set) var announced: Set<Key> = []
    private(set) var isWarmedUp = false

    /// - Returns: the crossings worth announcing now (at most one per window, the highest) and the memory to keep.
    static func evaluate(snapshot: UsageSnapshot, thresholds: UsageThresholds, memory: ThresholdMemory) -> (crossings: [ThresholdCrossing], memory: ThresholdMemory) {
        var next = memory
        var crossings: [ThresholdCrossing] = []

        for kind in UsageWindowKind.allCases {
            guard let window = snapshot[kind], let resetsAt = window.resetsAt else { continue }
            // Keys from an earlier window of this kind are history now.
            next.announced = next.announced.filter { $0.kind != kind || $0.resetsAt == resetsAt }

            let crossed = thresholds.ordered.filter { window.utilization >= $0 }
            let fresh = crossed.filter { !next.announced.contains(Key(kind: kind, threshold: $0, resetsAt: resetsAt)) }
            for threshold in crossed {
                next.announced.insert(Key(kind: kind, threshold: threshold, resetsAt: resetsAt))
            }
            if memory.isWarmedUp, let highest = fresh.max() {
                crossings.append(ThresholdCrossing(kind: kind, threshold: highest, window: window))
            }
        }
        next.isWarmedUp = true
        return (crossings, next)
    }
}

// MARK: Polling discipline

/// Cadence rules for the official endpoint, which is account-wide and aggressively rate limited.
nonisolated enum UsagePolling {
    /// Never below five minutes; the limiter is shared with every Claude Code session on the account.
    static let interval: TimeInterval = 300
    /// A 429 keeps coming back with `retry-after: 0` until the account goes quiet, so back off hard.
    static let rateLimitCooldown: TimeInterval = 900
    /// Give Wi-Fi and the CLI's own token refresh a moment after the lid opens.
    static let wakeGrace: TimeInterval = 60
    /// Readings older than this are drawn dimmed.
    static let staleAfter: TimeInterval = 900
    /// How often the credential store's metadata is checked while waiting for a sign-in.
    static let signInWatchInterval: TimeInterval = 5

    /// A poll can start when nothing forbids it: no cooldown in force and no fresh reading.
    static func shouldPoll(now: Date, lastPoll: Date?, cooldownUntil: Date?) -> Bool {
        if let cooldownUntil, now < cooldownUntil { return false }
        guard let lastPoll else { return true }
        return now.timeIntervalSince(lastPoll) >= interval - 1
    }

    /// After waking, refresh only if the last reading is old enough to matter; a short nap should
    /// not add an off-schedule request to the shared limiter.
    static func shouldRefreshAfterWake(lastPoll: Date?, now: Date) -> Bool {
        guard let lastPoll else { return true }
        return now.timeIntervalSince(lastPoll) >= interval / 2
    }

    static func isStale(fetchedAt: Date?, now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) > staleAfter
    }
}
