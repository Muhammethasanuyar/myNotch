import Foundation
import Observation

/// Both sources of builds in one list: Xcode on this Mac and GitHub Actions through `gh`.
@MainActor
@Observable
final class CIService {
    private(set) var runs: [CIRun] = []
    var onChange: (() -> Void)?
    /// A run finished since the last look; the module turns it into a popup.
    var onFinished: ((CIRun) -> Void)?

    let xcode: XcodeBuildWatcher
    let github: GitHubRunsService
    var xcodeEnabled = true {
        didSet { if xcodeEnabled != oldValue { syncXcode() } }
    }
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var primed = false
    @ObservationIgnored private var isStarted = false

    init(xcode: XcodeBuildWatcher = XcodeBuildWatcher(), github: GitHubRunsService = GitHubRunsService()) {
        self.xcode = xcode
        self.github = github
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        xcode.onChange = { [weak self] in self?.rebuild() }
        github.onChange = { [weak self] in self?.rebuild() }
        syncXcode()
        github.start()
    }

    func stop() {
        isStarted = false
        xcode.stop()
        github.stop()
        runs = []
        seen = []
        primed = false
    }

    /// The card is showing; GitHub is asked more often while it is.
    func setCardVisible(_ visible: Bool) {
        github.isCardOpen = visible
    }

    private func syncXcode() {
        guard isStarted else { return }
        if xcodeEnabled { xcode.start() } else { xcode.stop(); rebuild() }
    }

    private func rebuild() {
        let now = Date()
        runs = CIRules.merged(xcode: xcodeEnabled ? xcode.runs : [], github: github.runs)
        if primed {
            for run in CIRules.newRuns(runs, seen: seen, now: now) {
                seen.insert(run.id)
                onFinished?(run)
            }
        } else if !runs.isEmpty {
            // History is not news: the first list only primes the memory.
            seen.formUnion(runs.filter { !$0.isRunning }.map(\.id))
            primed = true
        }
        seen.formUnion(runs.filter { !$0.isRunning }.map(\.id))
        onChange?()
    }
}
