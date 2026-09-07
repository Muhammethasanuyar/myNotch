import XCTest
@testable import MyNotch

final class CIRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ id: String, status: CIStatus, finished: TimeInterval? = -10, source: CISource = .github(repo: "o/r")) -> CIRun {
        CIRun(id: id, source: source, title: id, subtitle: nil, status: status, finishedAt: finished.map { now.addingTimeInterval($0) }, url: nil, errorCount: 0, warningCount: 0)
    }

    func testXcodeStatusMapping() {
        XCTAssertEqual(CIRules.status(highLevelStatus: "S", errors: 0, warnings: 0), .success)
        XCTAssertEqual(CIRules.status(highLevelStatus: "W", errors: 0, warnings: 0), .warning)
        XCTAssertEqual(CIRules.status(highLevelStatus: "E", errors: 0, warnings: 0), .failure)
        XCTAssertEqual(CIRules.status(highLevelStatus: "S", errors: 2, warnings: 0), .failure, "the counts win")
        XCTAssertEqual(CIRules.status(highLevelStatus: "S", errors: 0, warnings: 3), .warning)
        XCTAssertEqual(CIRules.status(highLevelStatus: nil, errors: 0, warnings: 0), .unknown)
    }

    func testGitHubStatusMapping() {
        XCTAssertEqual(CIRules.status(ghStatus: "in_progress", conclusion: ""), .running, "an empty conclusion, not null, while running")
        XCTAssertEqual(CIRules.status(ghStatus: "queued", conclusion: nil), .running)
        XCTAssertEqual(CIRules.status(ghStatus: "completed", conclusion: "success"), .success)
        XCTAssertEqual(CIRules.status(ghStatus: "completed", conclusion: "failure"), .failure)
        XCTAssertEqual(CIRules.status(ghStatus: "completed", conclusion: "timed_out"), .failure)
        XCTAssertEqual(CIRules.status(ghStatus: "completed", conclusion: "cancelled"), .cancelled)
        XCTAssertEqual(CIRules.status(ghStatus: "completed", conclusion: "skipped"), .cancelled)
        XCTAssertEqual(CIRules.status(ghStatus: "completed", conclusion: "action_required"), .warning)
        XCTAssertEqual(CIRules.status(ghStatus: "completed", conclusion: "weird"), .unknown)
        XCTAssertEqual(CIRules.status(ghStatus: nil, conclusion: nil), .unknown)
    }

    func testDates() {
        XCTAssertEqual(CIRules.date(fromRecordingTime: 810432612.622895)?.timeIntervalSinceReferenceDate ?? 0, 810432612.622895, accuracy: 0.001)
        XCTAssertNil(CIRules.date(fromRecordingTime: nil))
        XCTAssertNil(CIRules.date(fromRecordingTime: 0), "a zero stop time is still recording")
        XCTAssertEqual(CIRules.date(iso: "2026-09-07T00:10:51Z"), ISO8601DateFormatter().date(from: "2026-09-07T00:10:51Z"))
        XCTAssertNotNil(CIRules.date(iso: "2026-09-07T00:10:51.500Z"), "fractions are tolerated")
        XCTAssertNil(CIRules.date(iso: nil))
    }

    func testOnlyFreshUnseenFinishedRunsAreNews() {
        let fresh = run("a", status: .success)
        let seen = run("b", status: .failure)
        let old = run("c", status: .failure, finished: -900)
        let running = run("d", status: .running, finished: nil)
        let unknown = run("e", status: .unknown)
        XCTAssertEqual(CIRules.newRuns([fresh, seen, old, running, unknown], seen: ["b"], now: now).map(\.id), ["a"])
    }

    func testRepoParsing() {
        XCTAssertEqual(CIRules.parseRepos("Muhammethasanuyar/myNotch, cli/cli\nfoo/bar"), ["Muhammethasanuyar/myNotch", "cli/cli", "foo/bar"])
        XCTAssertEqual(CIRules.parseRepos(" a/b ,, a/B , c "), ["a/b"], "duplicates (any case) and invalid entries are dropped")
        XCTAssertEqual(CIRules.parseRepos("not-a-repo a/b/c owner/"), [])
        XCTAssertEqual(CIRules.parseRepos("a/1 b/2 c/3 d/4 e/5 f/6 g/7").count, 5, "capped")
        XCTAssertTrue(CIRules.isValidRepo("some.org/some-repo_1"))
        XCTAssertFalse(CIRules.isValidRepo("bad repo/x"))
    }

    func testCadence() {
        XCTAssertEqual(CIRules.nextInterval(hasRunningRun: true, cardOpen: false, configured: 60), 60)
        XCTAssertEqual(CIRules.nextInterval(hasRunningRun: false, cardOpen: true, configured: 120), 120)
        XCTAssertEqual(CIRules.nextInterval(hasRunningRun: true, cardOpen: true, configured: 30), 60, "never below the floor")
        XCTAssertEqual(CIRules.nextInterval(hasRunningRun: false, cardOpen: false, configured: 60), 600)
        XCTAssertTrue(CIRules.shouldPoll(now: now, lastPoll: nil, interval: 60))
        XCTAssertFalse(CIRules.shouldPoll(now: now, lastPoll: now.addingTimeInterval(-30), interval: 60))
        XCTAssertTrue(CIRules.shouldPoll(now: now, lastPoll: now.addingTimeInterval(-61), interval: 60))
        XCTAssertTrue(CIRules.shouldRefreshAfterWake(lastPoll: now.addingTimeInterval(-40), now: now, interval: 60))
        XCTAssertFalse(CIRules.shouldRefreshAfterWake(lastPoll: now.addingTimeInterval(-20), now: now, interval: 60))
        XCTAssertEqual(CIRules.snappedPollInterval(90), 60)
        XCTAssertEqual(CIRules.snappedPollInterval(1000), 300)
    }

    func testMergingAndPresentation() {
        let bundle = Bundle(for: CIRulesTests.self)
        let xcode = (0..<7).map { run("x\($0)", status: .success, finished: Double(-$0), source: .xcode(project: "MyNotch")) }
        let github = [run("g1", status: .running, finished: nil), run("g2", status: .failure, finished: -5)]
        let merged = CIRules.merged(xcode: xcode, github: github, keep: 5)
        XCTAssertEqual(merged.count, 7, "five Xcode runs and two GitHub runs")
        XCTAssertEqual(merged.first?.id, "g1", "running first")
        XCTAssertEqual(merged[1].id, "x0", "then newest")
        XCTAssertEqual(CIRules.activity(github), .live)
        XCTAssertEqual(CIRules.activity(xcode), .idle)
        let failed = CIRun(id: "gh:1", source: .github(repo: "cli/cli"), title: "Fix thing", subtitle: "CI · main", status: .failure, finishedAt: now, url: nil, errorCount: 0, warningCount: 0)
        let event = CIRules.event(for: failed, moduleID: "ci", bundle: bundle)
        XCTAssertEqual(event.title, "cli/cli — failed")
        XCTAssertEqual(event.detail, "CI · main")
        XCTAssertEqual(event.symbolName, "xmark.octagon.fill")
        let warned = CIRun(id: "xcode:1", source: .xcode(project: "MyNotch"), title: "MyNotch", subtitle: "MyNotch project", status: .warning, finishedAt: now, url: nil, errorCount: 0, warningCount: 3)
        XCTAssertEqual(CIRules.event(for: warned, moduleID: "ci", bundle: bundle).title, "MyNotch — warnings")
        XCTAssertEqual(CIRules.countsText(warned, bundle: bundle), "3 warnings")
        XCTAssertNil(CIRules.countsText(failed, bundle: bundle))
    }
}

final class CIDecodingTests: XCTestCase {
    /// A literal copy of an entry Xcode 26.4 wrote for this very project (2026-09-07), plus one
    /// still recording and one without observables.
    private let manifest = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>logFormatVersion</key><integer>12</integer>
      <key>logs</key><dict>
        <key>90E2F9EC-0C95-49E6-87FB-1AC57374B685</key><dict>
          <key>className</key><string>IDECommandLineBuildLog</string>
          <key>domainType</key><string>Xcode.IDEActivityLogDomainType.BuildLog</string>
          <key>fileName</key><string>90E2F9EC-0C95-49E6-87FB-1AC57374B685.xcactivitylog</string>
          <key>hasPrimaryLog</key><true/>
          <key>primaryObservable</key><dict>
            <key>highLevelStatus</key><string>W</string>
            <key>totalNumberOfAnalyzerIssues</key><integer>0</integer>
            <key>totalNumberOfErrors</key><integer>0</integer>
            <key>totalNumberOfTestFailures</key><integer>0</integer>
            <key>totalNumberOfWarnings</key><integer>1</integer>
          </dict>
          <key>schemeIdentifier-containerName</key><string>MyNotch project</string>
          <key>schemeIdentifier-schemeName</key><string>MyNotch</string>
          <key>schemeIdentifier-sharedScheme</key><integer>1</integer>
          <key>signature</key><string>Testing project MyNotch with scheme MyNotch</string>
          <key>timeStartedRecording</key><real>810432610.862773</real>
          <key>timeStoppedRecording</key><real>810432612.622895</real>
          <key>title</key><string>Testing project MyNotch with scheme MyNotch</string>
          <key>uniqueIdentifier</key><string>90E2F9EC-0C95-49E6-87FB-1AC57374B685</string>
        </dict>
        <key>RUNNING</key><dict>
          <key>schemeIdentifier-schemeName</key><string>MyNotch</string>
          <key>timeStartedRecording</key><real>810432700</real>
          <key>title</key><string>Build MyNotch</string>
        </dict>
        <key>BARE</key><dict>
          <key>title</key><string>Something odd</string>
          <key>timeStoppedRecording</key><real>810432000</real>
        </dict>
      </dict>
    </dict></plist>
    """

    func testTheRealManifestDecodes() throws {
        let decoded = try BuildLogManifest.decode(Data(manifest.utf8))
        XCTAssertEqual(decoded.logFormatVersion, 12)
        XCTAssertEqual(decoded.logs.count, 3)
        let runs = decoded.runs(project: "MyNotch")
        let real = runs.first { $0.id == "xcode:90E2F9EC-0C95-49E6-87FB-1AC57374B685" }
        XCTAssertEqual(real?.title, "MyNotch", "the scheme, not the CLI title")
        XCTAssertEqual(real?.subtitle, "MyNotch project")
        XCTAssertEqual(real?.status, .warning)
        XCTAssertEqual(real?.warningCount, 1)
        XCTAssertEqual(real?.finishedAt?.timeIntervalSinceReferenceDate ?? 0, 810432612.622895, accuracy: 0.001)
        let running = runs.first { $0.id == "xcode:RUNNING" }
        XCTAssertEqual(running?.status, .running, "no stop time means still recording")
        XCTAssertNil(running?.finishedAt)
        let bare = runs.first { $0.id == "xcode:BARE" }
        XCTAssertEqual(bare?.status, .unknown, "no observable, no verdict")
        XCTAssertEqual(bare?.title, "Something odd")
    }

    func testCorruptManifestsFailLoudlyAndEmptyOnesDecode() throws {
        XCTAssertThrowsError(try BuildLogManifest.decode(Data("not a plist".utf8)))
        let empty = try BuildLogManifest.decode(Data("<plist version=\"1.0\"><dict><key>logs</key><dict/></dict></plist>".utf8))
        XCTAssertTrue(empty.logs.isEmpty)
    }

    /// A live `gh run list --json` answer for this repository (2026-09-07).
    private let ghSample = #"""
    [{"conclusion":"","databaseId":34068969427,"displayTitle":"feat(downloads): show browser downloads in the notch","event":"push","headBranch":"main","name":"CI","status":"in_progress","updatedAt":"2026-09-07T00:10:51Z","url":"https://github.com/Muhammethasanuyar/myNotch/actions/runs/34068969427","workflowName":"CI"},{"conclusion":"success","databaseId":34068677385,"displayTitle":"feat(audio): announce the output device when it changes","event":"push","headBranch":"main","name":"CI","status":"completed","updatedAt":"2026-09-07T00:07:03Z","url":"https://github.com/Muhammethasanuyar/myNotch/actions/runs/34068677385","workflowName":"CI"},{"status":"completed","conclusion":"failure"}]
    """#

    func testTheLiveGitHubSampleParses() throws {
        let runs = try GHRuns.parse(Data(ghSample.utf8), repo: "Muhammethasanuyar/myNotch")
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0].id, "gh:34068969427")
        XCTAssertEqual(runs[0].status, .running, "empty conclusion while in progress")
        XCTAssertEqual(runs[0].title, "feat(downloads): show browser downloads in the notch")
        XCTAssertEqual(runs[0].subtitle, "CI · main")
        XCTAssertEqual(runs[0].url?.absoluteString, "https://github.com/Muhammethasanuyar/myNotch/actions/runs/34068969427")
        XCTAssertEqual(runs[1].status, .success)
        XCTAssertEqual(runs[1].finishedAt, ISO8601DateFormatter().date(from: "2026-09-07T00:07:03Z"))
        XCTAssertEqual(runs[2].status, .failure, "a run missing most fields still gets its verdict")
        XCTAssertTrue(runs[2].id.hasPrefix("gh:"))
        XCTAssertEqual(GHRuns.arguments(repo: "o/r", limit: 5).prefix(3), ["run", "list", "--repo"])
        XCTAssertEqual(GHLocator.candidateDirectories(home: "/Users/x"), ["/opt/homebrew/bin", "/usr/local/bin", "/Users/x/.local/bin", "/usr/bin"])
        XCTAssertNil(GHLocator.locate(home: "/Users/x", override: nil, directories: ["/nope"], isExecutable: { _ in false }))
        XCTAssertEqual(GHLocator.locate(home: "/Users/x", override: nil, directories: ["/a", "/b"], isExecutable: { $0 == "/b/gh" })?.path, "/b/gh")
        XCTAssertEqual(GHLocator.locate(home: "/Users/x", override: "/custom/gh", directories: [], isExecutable: { $0 == "/custom/gh" })?.path, "/custom/gh")
        XCTAssertEqual(SettingsKey.ciGHPath.rawValue, GHLocator.pathOverrideKey)
    }
}
