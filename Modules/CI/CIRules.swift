import Foundation

nonisolated enum CIStatus: Equatable, Sendable {
    case running
    case success
    case warning
    case failure
    case cancelled
    case unknown
}

nonisolated enum CISource: Equatable, Hashable, Sendable {
    case xcode(project: String)
    case github(repo: String)
}

/// One build or workflow run, wherever it ran.
nonisolated struct CIRun: Equatable, Sendable, Identifiable {
    /// `xcode:<uniqueIdentifier>` or `gh:<databaseId>`.
    let id: String
    let source: CISource
    /// The scheme, or the commit/workflow title.
    let title: String
    /// The project, or "workflow · branch".
    let subtitle: String?
    let status: CIStatus
    let finishedAt: Date?
    let url: URL?
    let errorCount: Int
    let warningCount: Int

    var isRunning: Bool { status == .running }
}

/// Pure decisions of the builds module: status mapping for both sources, what counts as news,
/// repo parsing, and how often GitHub may be asked.
nonisolated enum CIRules {
    static let repoLimit = 5
    /// While a watched run is in flight or the card is open.
    static let activeInterval: TimeInterval = 60
    /// Otherwise.
    static let idleInterval: TimeInterval = 600
    static let pollChoices: [TimeInterval] = [60, 120, 300]
    /// A build that finished longer ago than this is history, not news.
    static let freshWindow: TimeInterval = 300
    static let popupDuration: TimeInterval = 3
    static let keepRuns = 5

    // MARK: Status

    /// Xcode's manifest: `S` success, `W` warnings, `E` errors; the counts win when they disagree.
    static func status(highLevelStatus: String?, errors: Int, warnings: Int) -> CIStatus {
        if errors > 0 || highLevelStatus == "E" { return .failure }
        if warnings > 0 || highLevelStatus == "W" { return .warning }
        return highLevelStatus == "S" ? .success : .unknown
    }

    /// GitHub: `status` is queued/in_progress/waiting/requested/pending/completed and `conclusion`
    /// is an empty string (not null) while a run is going.
    static func status(ghStatus: String?, conclusion: String?) -> CIStatus {
        guard ghStatus == "completed" else {
            switch ghStatus {
            case "queued", "in_progress", "waiting", "requested", "pending": return .running
            default: return .unknown
            }
        }
        switch conclusion ?? "" {
        case "success": return .success
        case "failure", "timed_out", "startup_failure": return .failure
        case "cancelled", "skipped": return .cancelled
        case "action_required", "neutral", "stale": return .warning
        default: return .unknown
        }
    }

    // MARK: Dates

    /// Xcode's `timeStoppedRecording` is CFAbsoluteTime (seconds since 2001).
    static func date(fromRecordingTime value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: value)
    }

    /// GitHub's `updatedAt`: ISO-8601 without fractions.
    static func date(iso text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ISO8601DateFormatter().date(from: text) ?? fractional.date(from: text)
    }

    // MARK: News

    /// Finished runs not yet announced and recent enough to matter.
    static func newRuns(_ runs: [CIRun], seen: Set<String>, now: Date) -> [CIRun] {
        runs.filter { run in
            guard !run.isRunning, run.status != .unknown, !seen.contains(run.id), let finished = run.finishedAt else { return false }
            return now.timeIntervalSince(finished) < freshWindow
        }
    }

    // MARK: Repositories

    static func isValidRepo(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
    }

    /// `owner/repo` entries separated by commas, spaces or newlines; invalid and duplicate ones dropped.
    static func parseRepos(_ text: String, limit: Int = repoLimit) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.split(whereSeparator: { $0 == "," || $0.isWhitespace || $0.isNewline }) {
            let candidate = String(raw)
            guard isValidRepo(candidate), seen.insert(candidate.lowercased()).inserted else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: Cadence

    static func snappedPollInterval(_ value: TimeInterval) -> TimeInterval {
        pollChoices.min { abs($0 - value) < abs($1 - value) } ?? activeInterval
    }

    static func nextInterval(hasRunningRun: Bool, cardOpen: Bool, configured: TimeInterval) -> TimeInterval {
        (hasRunningRun || cardOpen) ? max(activeInterval, configured) : idleInterval
    }

    static func shouldPoll(now: Date, lastPoll: Date?, interval: TimeInterval) -> Bool {
        guard let lastPoll else { return true }
        return now.timeIntervalSince(lastPoll) >= interval
    }

    /// After a wake, ask again only if the last answer is more than half an interval old.
    static func shouldRefreshAfterWake(lastPoll: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastPoll else { return true }
        return now.timeIntervalSince(lastPoll) > interval / 2
    }

    // MARK: Presentation

    static func symbolName(_ status: CIStatus) -> String {
        switch status {
        case .running: "hammer.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func statusTitle(_ status: CIStatus, bundle: Bundle = .main) -> String {
        switch status {
        case .running: String(localized: "ci.status.running", defaultValue: "Running", bundle: bundle)
        case .success: String(localized: "ci.status.success", defaultValue: "Succeeded", bundle: bundle)
        case .warning: String(localized: "ci.status.warning", defaultValue: "Warnings", bundle: bundle)
        case .failure: String(localized: "ci.status.failure", defaultValue: "Failed", bundle: bundle)
        case .cancelled: String(localized: "ci.status.cancelled", defaultValue: "Cancelled", bundle: bundle)
        case .unknown: String(localized: "ci.status.unknown", defaultValue: "Unknown", bundle: bundle)
        }
    }

    /// "3 errors · 1 warning" when there is something to count.
    static func countsText(_ run: CIRun, bundle: Bundle = .main) -> String? {
        var parts: [String] = []
        if run.errorCount > 0 { parts.append(String(localized: "ci.counts.errors", defaultValue: "\(run.errorCount) errors", bundle: bundle)) }
        if run.warningCount > 0 { parts.append(String(localized: "ci.counts.warnings", defaultValue: "\(run.warningCount) warnings", bundle: bundle)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func event(for run: CIRun, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        let subject: String = switch run.source {
        case .xcode(let project): project
        case .github(let repo): repo
        }
        return NotchEvent(
            moduleID: moduleID,
            title: String(localized: "ci.event.title", defaultValue: "\(subject) — \(statusTitle(run.status, bundle: bundle).lowercased())", bundle: bundle),
            detail: countsText(run, bundle: bundle) ?? run.subtitle ?? run.title,
            symbolName: symbolName(run.status),
            duration: popupDuration
        )
    }

    static func activity(_ runs: [CIRun]) -> ModuleActivity {
        runs.contains(where: \.isRunning) ? .live : .idle
    }

    /// Running first, then newest; at most `keep` per source.
    static func merged(xcode: [CIRun], github: [CIRun], keep: Int = keepRuns) -> [CIRun] {
        func trimmed(_ runs: [CIRun]) -> [CIRun] {
            Dictionary(grouping: runs, by: \.source).values.flatMap { group in
                Array(group.sorted(by: order).prefix(keep))
            }
        }
        return (trimmed(xcode) + trimmed(github)).sorted(by: order)
    }

    private static func order(_ a: CIRun, _ b: CIRun) -> Bool {
        if a.isRunning != b.isRunning { return a.isRunning }
        return (a.finishedAt ?? .distantPast) > (b.finishedAt ?? .distantPast)
    }
}
