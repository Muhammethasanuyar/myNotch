import AppKit
import Foundation
import Observation
import os

// Privacy: this runs the user's own `gh` command line tool. MyNotch stores no GitHub token and
// never talks to GitHub itself; `gh` sends its own credentials to api.github.com and only the run
// list of the repositories named in Settings comes back. Nothing else leaves this Mac.

/// The `gh run list` call, as pure pieces.
nonisolated enum GHRuns {
    static let fields = "status,conclusion,name,headBranch,displayTitle,updatedAt,url,databaseId,workflowName"
    static let timeout: TimeInterval = 20

    static func arguments(repo: String, limit: Int) -> [String] {
        ["run", "list", "--repo", repo, "--limit", String(limit), "--json", fields]
    }

    static let authArguments = ["auth", "status"]

    /// A trimmed PATH so `gh` finds its helpers, and no prompts, colours or update nags.
    static func environment(binDirectory: String, home: String) -> [String: String] {
        [
            "PATH": "\(binDirectory):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home,
            "NO_COLOR": "1",
            "GH_NO_UPDATE_NOTIFIER": "1",
            "GH_PROMPT_DISABLED": "1"
        ]
    }

    /// Every field is optional; `conclusion` is `""` while a run is going.
    struct Run: Decodable {
        var status: String?
        var conclusion: String?
        var name: String?
        var headBranch: String?
        var displayTitle: String?
        var updatedAt: String?
        var url: String?
        var databaseId: Int?
        var workflowName: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            conclusion = try? c.decodeIfPresent(String.self, forKey: .conclusion)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            headBranch = try? c.decodeIfPresent(String.self, forKey: .headBranch)
            displayTitle = try? c.decodeIfPresent(String.self, forKey: .displayTitle)
            updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
            url = try? c.decodeIfPresent(String.self, forKey: .url)
            databaseId = try? c.decodeIfPresent(Int.self, forKey: .databaseId)
            workflowName = try? c.decodeIfPresent(String.self, forKey: .workflowName)
        }

        private enum CodingKeys: String, CodingKey { case status, conclusion, name, headBranch, displayTitle, updatedAt, url, databaseId, workflowName }
    }

    static func parse(_ data: Data, repo: String) throws -> [CIRun] {
        try JSONDecoder().decode([Run].self, from: data).enumerated().map { index, run in
            let status = CIRules.status(ghStatus: run.status, conclusion: run.conclusion)
            let subtitle = [run.workflowName ?? run.name, run.headBranch].compactMap { $0 }.joined(separator: " · ")
            return CIRun(
                id: "gh:" + (run.databaseId.map(String.init) ?? "\(repo)#\(index)"),
                source: .github(repo: repo),
                title: run.displayTitle ?? run.name ?? repo,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                status: status,
                finishedAt: status == .running ? nil : CIRules.date(iso: run.updatedAt),
                url: run.url.flatMap(URL.init(string:)),
                errorCount: 0,
                warningCount: 0
            )
        }
    }
}

/// How the GitHub half is doing, for the pane and the Setup row.
nonisolated enum CIGitHubState: Equatable, Sendable {
    /// No repositories configured.
    case off
    case missing
    case notAuthenticated
    case ready
    case failed(String)
}

/// Polls GitHub Actions through `gh`: often while a run is in flight or the card is open, slowly
/// otherwise, never when no repository is configured.
@MainActor
@Observable
final class GitHubRunsService {
    private(set) var runs: [CIRun] = []
    private(set) var state: CIGitHubState = .off
    /// Repositories whose last call failed, with the reason — the others keep working.
    private(set) var repoErrors: [String: String] = [:]
    private(set) var lastPollAt: Date?
    var repos: [String] = [] {
        didSet { if repos != oldValue { restartPolling() } }
    }
    var pollInterval: TimeInterval = CIRules.activeInterval
    var isCardOpen = false {
        didSet { if isCardOpen, !oldValue { refreshIfStale() } }
    }
    var onChange: (() -> Void)?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "ci")

    func start() {
        guard !isStarted else { return }
        isStarted = true
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfStale() }
        }
        restartPolling()
    }

    func stop() {
        isStarted = false
        pollTask?.cancel()
        pollTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        runs = []
        state = .off
        onChange?()
    }

    func refresh() {
        Task { await pollOnce() }
    }

    private func refreshIfStale() {
        guard isStarted, !repos.isEmpty else { return }
        let interval = CIRules.nextInterval(hasRunningRun: runs.contains(where: \.isRunning), cardOpen: isCardOpen, configured: pollInterval)
        if CIRules.shouldRefreshAfterWake(lastPoll: lastPollAt, now: Date(), interval: interval) { refresh() }
    }

    private func restartPolling() {
        pollTask?.cancel()
        pollTask = nil
        guard isStarted else { return }
        guard !repos.isEmpty else {
            runs = []
            state = .off
            onChange?()
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await pollOnce()
                let interval = CIRules.nextInterval(hasRunningRun: runs.contains(where: \.isRunning), cardOpen: isCardOpen, configured: pollInterval)
                // A suspending clock: a closed lid does not queue a burst of polls.
                try? await Task.sleep(for: .seconds(interval), clock: .suspending)
            }
        }
    }

    private func pollOnce() async {
        guard isStarted, !repos.isEmpty else { return }
        guard let gh = GHLocator.locate() else {
            state = .missing
            onChange?()
            return
        }
        let environment = GHRuns.environment(binDirectory: gh.deletingLastPathComponent().path, home: NSHomeDirectory())
        if state == .off || state == .missing || state == .notAuthenticated {
            let auth = try? await ProcessRunner.run(gh, arguments: GHRuns.authArguments, environment: environment, timeout: GHRuns.timeout)
            guard let auth, auth.status == 0 else {
                state = .notAuthenticated
                onChange?()
                return
            }
        }
        var collected: [CIRun] = []
        var errors: [String: String] = [:]
        for repo in repos {
            do {
                let result = try await ProcessRunner.run(gh, arguments: GHRuns.arguments(repo: repo, limit: CIRules.keepRuns), environment: environment, timeout: GHRuns.timeout)
                guard result.status == 0 else {
                    errors[repo] = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).suffix(200).description
                    continue
                }
                collected += try GHRuns.parse(result.stdout, repo: repo)
            } catch {
                errors[repo] = String(describing: error)
            }
        }
        guard isStarted else { return }
        lastPollAt = Date()
        runs = collected
        repoErrors = errors
        if errors.count == repos.count, let first = errors.values.first {
            state = .failed(first)
            Self.log.error("gh run list failed for every repository: \(first, privacy: .public)")
        } else {
            state = .ready
        }
        onChange?()
    }
}
