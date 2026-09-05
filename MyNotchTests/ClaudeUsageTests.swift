import XCTest
@testable import MyNotch

// MARK: - Credentials

final class ClaudeCredentialsTests: XCTestCase {
    private let blob = """
    {"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"sk-ant-ort01-def","expiresAt":1788000000000,"scopes":["user:inference","user:profile"],"subscriptionType":"max"}}
    """

    func testDecodesAJSONBlob() {
        let object = ClaudeCredentials.decodeBlob(Data((blob + "\n").utf8))
        XCTAssertNotNil(object?["claudeAiOauth"])
    }

    func testDecodesAHexBlobAsSecurityPrintsIt() {
        let hex = Data(blob.utf8).map { String(format: "%02x", $0) }.joined()
        let object = ClaudeCredentials.decodeBlob(Data((hex + "\n").utf8))
        XCTAssertNotNil(object?["claudeAiOauth"], "security -w hex-dumps secrets with unprintable bytes")
    }

    func testCredentialReadsTokenExpiryInMillisecondsAndPlan() throws {
        let credential = try XCTUnwrap(ClaudeCredentials.credential(fromBlob: Data(blob.utf8), source: .environment))
        XCTAssertEqual(credential.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 1_788_000_000))
        XCTAssertEqual(credential.subscriptionType, "max")
    }

    func testBlobWithoutATokenIsRejected() {
        XCTAssertNil(ClaudeCredentials.credential(fromBlob: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8), source: .environment))
        XCTAssertNil(ClaudeCredentials.credential(fromBlob: Data("not json".utf8), source: .environment))
    }

    func testServiceFilterAcceptsVariantsButNotSiblings() {
        XCTAssertTrue(ClaudeCredentials.isClaudeCredentialService("Claude Code-credentials"))
        XCTAssertTrue(ClaudeCredentials.isClaudeCredentialService("Claude Code-credentials-3f2a9c"))
        XCTAssertFalse(ClaudeCredentials.isClaudeCredentialService("Claude Code-doctor-probe"))
        XCTAssertFalse(ClaudeCredentials.isClaudeCredentialService("Claude Code"))
    }

    func testCredentialsFileFollowsTheConfigDirList() {
        XCTAssertEqual(ClaudeCredentials.credentialsFileURL(configDirectory: nil, home: "/Users/x").path, "/Users/x/.claude/.credentials.json")
        XCTAssertEqual(ClaudeCredentials.credentialsFileURL(configDirectory: "~/cfg", home: "/Users/x").path, "/Users/x/cfg/.credentials.json")
        XCTAssertEqual(ClaudeCredentials.credentialsFileURL(configDirectory: " /tmp/a , /tmp/b", home: "/Users/x").path, "/tmp/a/.credentials.json")
        XCTAssertEqual(ClaudeCredentials.credentialsFileURL(configDirectory: "", home: "/Users/x").path, "/Users/x/.claude/.credentials.json")
    }

    func testExpiryIsTreatedAMinuteEarly() {
        let expiry = Date(timeIntervalSince1970: 10_000)
        let credential = ClaudeCredential(accessToken: "t", expiresAt: expiry, subscriptionType: nil, source: .environment)
        XCTAssertFalse(credential.isExpired(at: expiry.addingTimeInterval(-61)))
        XCTAssertTrue(credential.isExpired(at: expiry.addingTimeInterval(-60)))
        XCTAssertFalse(ClaudeCredential(accessToken: "t", expiresAt: nil, subscriptionType: nil, source: .environment).isExpired())
    }

    func testSecurityArgumentsOmitAnEmptyAccount() {
        XCTAssertEqual(ClaudeCredentials.securityArguments(service: "S", account: ""), ["find-generic-password", "-s", "S", "-w"])
        XCTAssertEqual(ClaudeCredentials.securityArguments(service: "S", account: "me"), ["find-generic-password", "-s", "S", "-a", "me", "-w"])
    }
}

// MARK: - Fetcher

final class UsageFetcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRequestCarriesTheGatedHeaders() {
        let request = UsageFetcher.request(token: "tok")
        XCTAssertEqual(request.url, UsageFetcher.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), UsageFetcher.userAgent)
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testParsesBothWindowsWithEpochAndISODates() throws {
        let body = """
        {"five_hour":{"utilization":42,"resets_at":1800003600},"seven_day":{"utilization":7.5,"resets_at":"2027-01-19T03:14:07.000Z"}}
        """
        guard case .usage(let snapshot) = UsageFetcher.outcome(status: 200, body: Data(body.utf8), now: now) else {
            return XCTFail("expected usage")
        }
        XCTAssertEqual(snapshot.fiveHour?.utilization ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(snapshot.sevenDay?.utilization ?? 0, 0.075, accuracy: 0.0001)
        XCTAssertEqual(snapshot.sevenDay?.resetsAt, ISO8601DateFormatter().date(from: "2027-01-19T03:14:07Z"))
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testWeeklySplitByModelUsesTheFullestWindow() throws {
        let body = """
        {"five_hour":{"utilization":10,"resets_at":1800003600},"seven_day_opus":{"utilization":61,"resets_at":1800300000},"seven_day_sonnet":{"utilization":12,"resets_at":1800300000}}
        """
        guard case .usage(let snapshot) = UsageFetcher.outcome(status: 200, body: Data(body.utf8), now: now) else {
            return XCTFail("expected usage")
        }
        XCTAssertEqual(snapshot.sevenDay?.utilization ?? 0, 0.61, accuracy: 0.0001)
        XCTAssertEqual(snapshot.weeklyByModel.keys.sorted(), ["opus", "sonnet"])
    }

    /// The `limits[]` array as the endpoint returned it on 2026-09-05 (percentages only).
    func testScopedLimitsComeFromTheLimitsArray() throws {
        let body = """
        {"five_hour":{"utilization":20,"resets_at":"2026-09-05T16:20:00.371894+00:00"},
         "seven_day":{"utilization":8,"resets_at":"2026-09-06T09:00:00.371913+00:00"},
         "seven_day_opus":null,"seven_day_sonnet":null,
         "limits":[
           {"group":"session","is_active":true,"kind":"session","percent":20,"resets_at":"2026-09-05T16:20:00.371894+00:00","scope":null,"severity":"normal"},
           {"group":"weekly","is_active":false,"kind":"weekly_all","percent":8,"resets_at":"2026-09-06T09:00:00.371913+00:00","scope":null,"severity":"normal"},
           {"group":"weekly","is_active":false,"kind":"weekly_scoped","percent":15,"resets_at":"2026-09-06T09:00:00.372120+00:00","scope":{"model":{"display_name":"Fable","id":null},"surface":null},"severity":"normal"}
         ]}
        """
        guard case .usage(let snapshot) = UsageFetcher.outcome(status: 200, body: Data(body.utf8), now: now) else {
            return XCTFail("expected usage")
        }
        XCTAssertEqual(snapshot.fiveHour?.utilization ?? 0, 0.20, accuracy: 0.0001)
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt, "six fractional digits still parse")
        XCTAssertEqual(snapshot.weeklyByModel, [:], "null per-model windows are not windows")
        let fable = try XCTUnwrap(snapshot.scopedLimits.first)
        XCTAssertEqual(snapshot.scopedLimits.count, 1, "entries with a null scope repeat the account windows")
        XCTAssertEqual(fable.name, "Fable")
        XCTAssertEqual(fable.kind, "weekly_scoped")
        XCTAssertEqual(fable.windowKind, .sevenDay)
        XCTAssertEqual(fable.window.utilization, 0.15, accuracy: 0.0001)
        XCTAssertEqual(fable.id, "scoped:sevenDay:Fable")
        XCTAssertEqual(snapshot.subjects.map(\.subject.id), ["fiveHour", "sevenDay", "scoped:sevenDay:Fable"])
    }

    func testUtilizationIsAPercentageEvenWhenTiny() {
        XCTAssertEqual(UsageFetcher.parseWindow(["utilization": 0.5])?.utilization ?? -1, 0.005, accuracy: 0.00001, "0.5 means half a percent, not fifty")
        XCTAssertEqual(UsageFetcher.parseWindow(["used_percent": 150])?.utilization, 1, "clamped")
        XCTAssertNil(UsageFetcher.parseWindow(["resets_at": 1]), "a window without a number is no reading")
    }

    func testStatusMapping() {
        XCTAssertEqual(UsageFetcher.outcome(status: 401, body: Data(), now: now), .unauthorized)
        XCTAssertEqual(UsageFetcher.outcome(status: 403, body: Data(), now: now), .reauthRequired)
        XCTAssertEqual(UsageFetcher.outcome(status: 429, body: Data(), now: now), .rateLimited)
        XCTAssertEqual(UsageFetcher.outcome(status: 503, body: Data(), now: now), .failed("HTTP 503"))
    }

    func testRateLimitInsideASuccessfulBody() {
        let body = #"{"error":{"type":"rate_limit_error","message":"slow down"}}"#
        XCTAssertEqual(UsageFetcher.outcome(status: 200, body: Data(body.utf8), now: now), .rateLimited)
    }

    func testUnreadableOrEmptyBodiesFail() {
        XCTAssertEqual(UsageFetcher.outcome(status: 200, body: Data("<html>".utf8), now: now), .failed("unreadable body"))
        XCTAssertEqual(UsageFetcher.outcome(status: 200, body: Data("{}".utf8), now: now), .failed("no usage windows in response"))
    }
}

// MARK: - Merge, thresholds, polling

final class UsageMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testAFailedPollKeepsThePreviousReadingUntilItsWindowResets() {
        let live = UsageWindow(utilization: 0.4, resetsAt: now.addingTimeInterval(600))
        let gone = UsageWindow(utilization: 0.9, resetsAt: now.addingTimeInterval(-1))
        let previous = UsageSnapshot(fiveHour: live, sevenDay: gone, fetchedAt: now.addingTimeInterval(-300))

        let merged = UsageMerge.merge(previous: previous, fetched: nil, now: now)
        XCTAssertEqual(merged?.fiveHour, live)
        XCTAssertNil(merged?.sevenDay, "a reading of a window that already reset is dropped")
        XCTAssertEqual(merged?.fetchedAt, previous.fetchedAt, "staleness is measured from the real reading")
    }

    func testASuccessfulPollReplacesWhatItReported() {
        let previous = UsageSnapshot(fiveHour: UsageWindow(utilization: 0.4, resetsAt: nil), sevenDay: UsageWindow(utilization: 0.2, resetsAt: nil), fetchedAt: now)
        let fetched = UsageSnapshot(fiveHour: UsageWindow(utilization: 0.5, resetsAt: nil), sevenDay: nil, fetchedAt: now.addingTimeInterval(300))
        let merged = UsageMerge.merge(previous: previous, fetched: fetched, now: now.addingTimeInterval(300))
        XCTAssertEqual(merged?.fiveHour?.utilization, 0.5)
        XCTAssertEqual(merged?.sevenDay?.utilization, 0.2, "a window the server left out keeps its last value")
        XCTAssertEqual(merged?.fetchedAt, fetched.fetchedAt)
    }

    func testScopedLimitsCarryForwardLikeTheWindows() {
        let fable = ScopedLimit(name: "Fable", kind: "weekly_scoped", windowKind: .sevenDay, window: UsageWindow(utilization: 0.15, resetsAt: now.addingTimeInterval(3600)))
        let gone = ScopedLimit(name: "Old", kind: "weekly_scoped", windowKind: .sevenDay, window: UsageWindow(utilization: 0.5, resetsAt: now.addingTimeInterval(-1)))
        let previous = UsageSnapshot(fiveHour: UsageWindow(utilization: 0.2, resetsAt: nil), sevenDay: nil, scopedLimits: [fable, gone], fetchedAt: now)
        let merged = UsageMerge.merge(previous: previous, fetched: nil, now: now)
        XCTAssertEqual(merged?.scopedLimits, [fable], "a scoped limit whose window reset is dropped like any other")
        let fresh = UsageSnapshot(fiveHour: nil, sevenDay: nil, scopedLimits: [], fetchedAt: now)
        XCTAssertEqual(UsageMerge.merge(previous: previous, fetched: fresh, now: now)?.scopedLimits, [], "a successful poll without the limit removes it")
    }

    func testNothingLeftMeansNoSnapshot() {
        let gone = UsageSnapshot(fiveHour: UsageWindow(utilization: 0.9, resetsAt: now.addingTimeInterval(-1)), sevenDay: nil, fetchedAt: now)
        XCTAssertNil(UsageMerge.merge(previous: gone, fetched: nil, now: now))
    }

    func testResetDetection() {
        let before = UsageWindow(utilization: 0.8, resetsAt: now)
        let after = UsageWindow(utilization: 0.02, resetsAt: now.addingTimeInterval(18_000))
        XCTAssertTrue(UsageMerge.didReset(previous: before, current: after))
        XCTAssertFalse(UsageMerge.didReset(previous: before, current: before))
        XCTAssertFalse(UsageMerge.didReset(previous: UsageWindow(utilization: 0.1, resetsAt: now), current: after), "a trivial old reading is not worth announcing")
    }
}

final class ThresholdMemoryTests: XCTestCase {
    private let reset = Date(timeIntervalSince1970: 5_000)
    private let thresholds = UsageThresholds()

    private func snapshot(fiveHour: Double, resetsAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(fiveHour: UsageWindow(utilization: fiveHour, resetsAt: resetsAt ?? reset), sevenDay: nil, fetchedAt: Date())
    }

    func testTheFirstReadingOnlyPrimesTheMemory() {
        let result = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.96), thresholds: thresholds, memory: ThresholdMemory())
        XCTAssertTrue(result.crossings.isEmpty, "opening the app at 96 % must not alert retroactively")
        XCTAssertTrue(result.memory.isWarmedUp)
    }

    func testACrossingIsAnnouncedOncePerWindow() {
        var memory = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.5), thresholds: thresholds, memory: ThresholdMemory()).memory
        let first = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.82), thresholds: thresholds, memory: memory)
        XCTAssertEqual(first.crossings.map(\.threshold), [0.8])
        memory = first.memory
        let again = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.85), thresholds: thresholds, memory: memory)
        XCTAssertTrue(again.crossings.isEmpty, "no spam while it stays above")
        memory = again.memory
        let dipAndBack = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.81), thresholds: thresholds,
                                                  memory: ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.7), thresholds: thresholds, memory: memory).memory)
        XCTAssertTrue(dipAndBack.crossings.isEmpty, "the same window does not re-announce the same threshold")
    }

    func testANewResetTimeAnnouncesAgain() {
        let memory = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.9), thresholds: thresholds, memory: ThresholdMemory()).memory
        let later = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.9, resetsAt: reset.addingTimeInterval(18_000)), thresholds: thresholds, memory: memory)
        XCTAssertEqual(later.crossings.map(\.threshold), [0.8])
        XCTAssertEqual(later.memory.announced.count, 1, "keys of the old window were forgotten")
    }

    func testTheHighestFreshThresholdWins() {
        let memory = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.1), thresholds: thresholds, memory: ThresholdMemory()).memory
        let jump = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.97), thresholds: thresholds, memory: memory)
        XCTAssertEqual(jump.crossings.map(\.threshold), [0.95], "one alert per window, the most severe")
    }

    func testInvertedThresholdsDisableAlerts() {
        let memory = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.1), thresholds: thresholds, memory: ThresholdMemory()).memory
        let result = ThresholdMemory.evaluate(snapshot: snapshot(fiveHour: 0.99), thresholds: UsageThresholds(warning: 0.9, critical: 0.5), memory: memory)
        XCTAssertTrue(result.crossings.isEmpty)
    }
}

final class UsagePollingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)

    func testPollingRespectsCooldownAndInterval() {
        XCTAssertTrue(UsagePolling.shouldPoll(now: now, lastPoll: nil, cooldownUntil: nil))
        XCTAssertFalse(UsagePolling.shouldPoll(now: now, lastPoll: nil, cooldownUntil: now.addingTimeInterval(1)))
        XCTAssertFalse(UsagePolling.shouldPoll(now: now, lastPoll: now.addingTimeInterval(-100), cooldownUntil: nil))
        XCTAssertTrue(UsagePolling.shouldPoll(now: now, lastPoll: now.addingTimeInterval(-300), cooldownUntil: nil))
    }

    func testAShortNapDoesNotEarnAnExtraRequest() {
        XCTAssertFalse(UsagePolling.shouldRefreshAfterWake(lastPoll: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(UsagePolling.shouldRefreshAfterWake(lastPoll: now.addingTimeInterval(-200), now: now))
        XCTAssertTrue(UsagePolling.shouldRefreshAfterWake(lastPoll: nil, now: now))
    }

    func testStaleness() {
        XCTAssertTrue(UsagePolling.isStale(fetchedAt: nil, now: now))
        XCTAssertFalse(UsagePolling.isStale(fetchedAt: now.addingTimeInterval(-600), now: now))
        XCTAssertTrue(UsagePolling.isStale(fetchedAt: now.addingTimeInterval(-1000), now: now))
    }
}

// MARK: - ccusage

final class CCUsageParserTests: XCTestCase {
    /// Captured from `ccusage@20 claude blocks --json --active --offline` on 2026-09-04.
    private let blocksJSON = """
    {"blocks":[{"actualEndTime":"2026-09-04T12:35:13.025Z","burnRate":{"costPerHour":0.0,"tokensPerMinute":250376.13,"tokensPerMinuteForIndicator":3279.57},"costUSD":0,"endTime":"2026-09-04T17:00:00.000Z","entries":15,"id":"2026-09-04T12:00:00.000Z","isActive":true,"isGap":false,"models":["claude-fable-5-1"],"projection":{"remainingMinutes":260,"totalCost":0.0,"totalTokens":69138919},"startTime":"2026-09-04T12:00:00.000Z","tokenCounts":{"cacheCreationInputTokens":312567,"cacheReadInputTokens":3675625,"inputTokens":4228,"outputTokens":48705},"totalTokens":4041125},
    {"id":"gap-1","startTime":"2026-09-04T05:00:00.000Z","endTime":"2026-09-04T12:00:00.000Z","isActive":false,"isGap":true,"tokenCounts":{},"totalTokens":0,"costUSD":0,"models":[]}]}
    """

    private let dailyJSON = """
    {"daily":[{"cacheCreationTokens":1707713,"cacheReadTokens":62103462,"date":"2026-09-04","inputTokens":30267,"modelBreakdowns":[{"cacheCreationTokens":125178,"cacheReadTokens":47422359,"cost":27.679159499999997,"inputTokens":130,"modelName":"claude-opus-5","outputTokens":108622},{"cacheCreationTokens":1582535,"cacheReadTokens":14681103,"cost":0.0,"inputTokens":30137,"modelName":"claude-fable-5-1","outputTokens":203469}],"modelsUsed":["claude-opus-5","claude-fable-5-1"],"outputTokens":312091,"totalCost":27.679159499999997,"totalTokens":64153533}],"totals":{"totalCost":27.679159499999997}}
    """

    func testDecodesTheRealBlocksShape() throws {
        let report = try CCUsageParser.blocks(from: Data(blocksJSON.utf8))
        XCTAssertEqual(report.blocks.count, 2)
        let active = try XCTUnwrap(report.activeBlock)
        XCTAssertEqual(active.id, "2026-09-04T12:00:00.000Z")
        XCTAssertEqual(active.tokenCounts.outputTokens, 48705)
        XCTAssertEqual(active.costUSD, 0, "an integer cost still decodes as Double")
        XCTAssertEqual(active.burnRate?.tokensPerMinute ?? 0, 250376.13, accuracy: 0.01)
        XCTAssertEqual(active.projection?.remainingMinutes, 260)
        XCTAssertEqual(active.endTime.timeIntervalSince(active.startTime), 5 * 3600)
        XCTAssertFalse(report.blocks[1].isActive)
    }

    func testDecodesTheRealDailyShape() throws {
        let report = try CCUsageParser.daily(from: Data(dailyJSON.utf8))
        let today = try XCTUnwrap(report.daily.first)
        XCTAssertEqual(today.date, "2026-09-04")
        XCTAssertEqual(today.totalCost, 27.6791595, accuracy: 0.0001)
        XCTAssertEqual(today.modelBreakdowns.map(\.modelName), ["claude-opus-5", "claude-fable-5-1"])
        XCTAssertEqual(today.totalTokens, 64_153_533)
    }

    func testSinceArgumentIsCompactLocalDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 1))!
        XCTAssertEqual(CCUsageParser.sinceArgument(for: date, calendar: calendar), "20260904")
    }

    func testModelFamilies() {
        XCTAssertEqual(CCUsageParser.modelFamily("claude-opus-5"), "Opus")
        XCTAssertEqual(CCUsageParser.modelFamily("claude-fable-5-1"), "Fable")
        XCTAssertEqual(CCUsageParser.modelFamily("claude-haiku-4-5-20251001"), "Haiku")
        XCTAssertEqual(CCUsageParser.modelFamily("mystery"), "mystery")
    }

    func testPrettyModelNames() {
        XCTAssertEqual(CCUsageParser.prettyModelName("claude-opus-5"), "Opus 5")
        XCTAssertEqual(CCUsageParser.prettyModelName("claude-fable-5-1"), "Fable 5.1")
        XCTAssertEqual(CCUsageParser.prettyModelName("claude-haiku-4-5-20251001"), "Haiku 4.5", "the release date is not part of the name")
        XCTAssertEqual(CCUsageParser.prettyModelName("claude-3-5-sonnet-20241022"), "Sonnet 3.5", "older names put the version first")
        XCTAssertEqual(CCUsageParser.prettyModelName("mystery-model"), "mystery-model")
    }

    func testModelSharesSplitBySpendAndFallBackToTokens() {
        let priced = [
            CCUsageDay.ModelBreakdown(modelName: "claude-opus-5", outputTokens: 100, cost: 30),
            CCUsageDay.ModelBreakdown(modelName: "claude-fable-5-1", outputTokens: 900, cost: 10)
        ]
        let bySpend = ModelShare.compute(priced)
        XCTAssertEqual(bySpend.map(\.name), ["Opus 5", "Fable 5.1"], "spend decides when the tool could price the work")
        XCTAssertEqual(bySpend[0].share, 0.75, accuracy: 0.0001)

        let unpriced = priced.map { CCUsageDay.ModelBreakdown(modelName: $0.modelName, outputTokens: $0.outputTokens, cost: 0) }
        let byTokens = ModelShare.compute(unpriced)
        XCTAssertEqual(byTokens.map(\.name), ["Fable 5.1", "Opus 5"], "without prices, output tokens decide")
        XCTAssertEqual(byTokens[0].share, 0.9, accuracy: 0.0001)

        XCTAssertEqual(ModelShare.compute([]), [])
        XCTAssertEqual(ModelShare.compute([CCUsageDay.ModelBreakdown(modelName: "claude-fable-5-1")]), [], "nothing done means no shares")
    }
}

final class CCUsageRunnerTests: XCTestCase {
    func testLocatePrefersABinaryOverNPX() {
        let dirs = ["/opt/homebrew/bin", "/Users/x/.nvm/versions/node/v24.0.0/bin"]
        let executables: Set<String> = ["/opt/homebrew/bin/npx", "/Users/x/.nvm/versions/node/v24.0.0/bin/ccusage", "/Users/x/.nvm/versions/node/v24.0.0/bin/npx"]
        XCTAssertEqual(
            CCUsageRunner.locate(home: "/Users/x", override: nil, directories: dirs, isExecutable: executables.contains),
            .binary(URL(fileURLWithPath: "/Users/x/.nvm/versions/node/v24.0.0/bin/ccusage"))
        )
        XCTAssertEqual(
            CCUsageRunner.locate(home: "/Users/x", override: nil, directories: dirs, isExecutable: { $0 == "/opt/homebrew/bin/npx" }),
            .npx(URL(fileURLWithPath: "/opt/homebrew/bin/npx"))
        )
        XCTAssertNil(CCUsageRunner.locate(home: "/Users/x", override: nil, directories: dirs, isExecutable: { _ in false }))
        XCTAssertEqual(
            CCUsageRunner.locate(home: "/Users/x", override: "/custom/ccusage", directories: dirs, isExecutable: { $0 == "/custom/ccusage" }),
            .binary(URL(fileURLWithPath: "/custom/ccusage"))
        )
    }

    func testNodeVersionsAreOrderedNewestFirst() {
        let dirs = CCUsageRunner.candidateDirectories(home: "/Users/x", nodeVersions: ["v20.9.0", "v24.13.0", "v22.1.0"])
        XCTAssertEqual(dirs.suffix(3).map { $0.components(separatedBy: "/")[6] }, ["v24.13.0", "v22.1.0", "v20.9.0"])
        XCTAssertEqual(dirs.first, "/opt/homebrew/bin")
    }

    func testNPXInvocationPinsThePackageAndBuildsAPath() {
        let launcher = CCUsageLauncher.npx(URL(fileURLWithPath: "/Users/x/.nvm/versions/node/v24.13.0/bin/npx"))
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .current, year: 2026, month: 9, day: 4, hour: 12))!
        let invocation = CCUsageRunner.invocation(launcher, command: CCUsageRunner.blocksCommand(now: now), home: "/Users/x", configDirectory: "/tmp/cfg")
        XCTAssertEqual(invocation.arguments, ["--yes", "ccusage@20", "claude", "blocks", "--json", "--since", "20260904", "--offline"],
                       "every block of the day, so the chart has bars and the active one is picked client-side")
        XCTAssertEqual(invocation.environment["PATH"], "/Users/x/.nvm/versions/node/v24.13.0/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(invocation.environment["CLAUDE_CONFIG_DIR"], "/tmp/cfg")
        XCTAssertEqual(invocation.environment["HOME"], "/Users/x")
    }

    func testBinaryInvocationPassesTheCommandThrough() {
        let launcher = CCUsageLauncher.binary(URL(fileURLWithPath: "/opt/homebrew/bin/ccusage"))
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .current, year: 2026, month: 9, day: 4, hour: 12))!
        let invocation = CCUsageRunner.invocation(launcher, command: CCUsageRunner.dailyCommand(now: now), home: "/Users/x", configDirectory: nil)
        XCTAssertEqual(invocation.executable.path, "/opt/homebrew/bin/ccusage")
        XCTAssertEqual(invocation.arguments, ["claude", "daily", "--json", "--since", "20260904", "--offline"])
        XCTAssertNil(invocation.environment["CLAUDE_CONFIG_DIR"])
    }
}

// MARK: - Paths and session tails

final class ClaudePathsTests: XCTestCase {
    func testConfigDirListWinsAndAcceptsProjectsItself() {
        let roots = ClaudePaths.projectsDirectories(
            environment: ["CLAUDE_CONFIG_DIR": "~/work/claude, /tmp/other/projects ,,/missing"],
            home: "/Users/x",
            exists: { $0 == "/Users/x/work/claude/projects" || $0 == "/tmp/other/projects" }
        )
        XCTAssertEqual(roots.map(\.path), ["/Users/x/work/claude/projects", "/tmp/other/projects"])
    }

    func testDefaultsAreBothRootsThatExist() {
        let roots = ClaudePaths.projectsDirectories(environment: [:], home: "/Users/x", exists: { $0 == "/Users/x/.claude/projects" })
        XCTAssertEqual(roots.map(\.path), ["/Users/x/.claude/projects"])
        let both = ClaudePaths.projectsDirectories(environment: ["XDG_CONFIG_HOME": "/Users/x/cfg"], home: "/Users/x", exists: { _ in true })
        XCTAssertEqual(both.map(\.path), ["/Users/x/cfg/claude/projects", "/Users/x/.claude/projects"])
    }
}

final class SessionTailParserTests: XCTestCase {
    private let lines = [
        #"ge":{"role":"user"},"cwd":"/cut/off"}"#,
        #"{"type":"user","cwd":"/Users/x/Projects/older","sessionId":"s1","timestamp":"2026-09-04T10:00:00.000Z"}"#,
        #"{"type":"assistant","cwd":"/Users/x/Projects/dynamic-notch","sessionId":"s2","timestamp":"2026-09-04T10:05:00.000Z","message":{"model":"claude-fable-5-1","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","message":{"model":"<synthetic>"}}"#,
        #"{"type":"custom-title","customTitle":"Notch hover"}"#,
        #"{"type":"assistant","cwd":"/Users/x/Projects/dynamic-notch","timestamp":"2026-09-04T10:06:00.000Z","message":{"model":"claude-fab"#
    ]

    func testDropsTheCutFirstLineAndTheUnfinishedLastOne() {
        let tail = SessionTailParser.parse(Data(lines.joined(separator: "\n").utf8), fromStart: false)
        XCTAssertEqual(tail.cwd, "/Users/x/Projects/dynamic-notch")
        XCTAssertEqual(tail.projectName, "dynamic-notch")
        XCTAssertEqual(tail.sessionID, "s2")
        XCTAssertEqual(tail.lastModel, "claude-fable-5-1", "synthetic models and the unfinished line are ignored")
        XCTAssertEqual(tail.customTitle, "Notch hover")
        XCTAssertEqual(tail.lastTimestamp, ISO8601DateFormatter().date(from: "2026-09-04T10:05:00Z"))
    }

    func testAWholeFileKeepsItsFirstLine() {
        let whole = Array(lines[1...2]).joined(separator: "\n") + "\n"
        let tail = SessionTailParser.parse(Data(whole.utf8), fromStart: true)
        XCTAssertEqual(tail.sessionID, "s2")
        XCTAssertEqual(SessionTailParser.parse(Data((lines[1] + "\n").utf8), fromStart: true).cwd, "/Users/x/Projects/older")
    }

    func testReadTailOfAShortFileIsFromStart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try (lines[1] + "\n").write(to: url, atomically: true, encoding: .utf8)
        let tail = try XCTUnwrap(SessionTailParser.readTail(of: url, bytes: 16))
        XCTAssertFalse(tail.fromStart, "a 16-byte window of a longer file is a cut")
        let whole = try XCTUnwrap(SessionTailParser.readTail(of: url))
        XCTAssertTrue(whole.fromStart)
        XCTAssertEqual(SessionTailParser.parse(whole).cwd, "/Users/x/Projects/older")
    }
}

// MARK: - Module rules

final class ClaudeUsageRulesTests: XCTestCase {
    /// A bundle with no Turkish strings, so the rules answer in the source language whatever the
    /// Mac's own language is.
    private let english = Bundle(for: ClaudeUsageRulesTests.self)

    func testActivity() {
        let thresholds = UsageThresholds()
        XCTAssertEqual(ClaudeUsageRules.activity(isWorking: true, fiveHour: nil, thresholds: thresholds), .live)
        XCTAssertEqual(ClaudeUsageRules.activity(isWorking: false, fiveHour: UsageWindow(utilization: 0.3, resetsAt: nil), thresholds: thresholds), .idle)
        XCTAssertEqual(ClaudeUsageRules.activity(isWorking: false, fiveHour: UsageWindow(utilization: 0.85, resetsAt: nil), thresholds: thresholds), .live)
    }

    func testFormatting() {
        XCTAssertEqual(ClaudeUsageRules.formatRemaining(30, bundle: english), "<1m")
        XCTAssertEqual(ClaudeUsageRules.formatRemaining(45 * 60, bundle: english), "45m")
        XCTAssertEqual(ClaudeUsageRules.formatRemaining(80 * 60, bundle: english), "1h 20m")
        XCTAssertEqual(ClaudeUsageRules.formatRemaining(3 * 3600, bundle: english), "3h")
        XCTAssertEqual(ClaudeUsageRules.formatRemaining(2 * 86_400 + 3 * 3600, bundle: english), "2d 3h")
        XCTAssertEqual(ClaudeUsageRules.percent(26, bundle: english), "26%", "a literal percent sign survives the format")
        XCTAssertEqual(ClaudeUsageRules.formatCost(4.2), "$4.20")
        XCTAssertEqual(ClaudeUsageRules.formatCost(127.4), "$127")
        XCTAssertEqual(ClaudeUsageRules.formatTokens(48_705), "48K")
        XCTAssertEqual(ClaudeUsageRules.formatTokens(64_153_533), "64.2M")
        XCTAssertEqual(ClaudeUsageRules.formatTokens(999), "999")
    }

    func testBurnDescription() {
        XCTAssertNil(ClaudeUsageRules.burnDescription(tokensPerMinute: nil, costPerHour: 10, projectedCost: 20, bundle: english))
        XCTAssertNil(ClaudeUsageRules.burnDescription(tokensPerMinute: 0, costPerHour: 10, projectedCost: 20, bundle: english))
        let unpriced = ClaudeUsageRules.burnDescription(tokensPerMinute: 3279.57, costPerHour: 0, projectedCost: 0, bundle: english)
        XCTAssertEqual(unpriced?.value, "3K tok/min")
        XCTAssertNil(unpriced?.detail, "no money to talk about")
        let priced = ClaudeUsageRules.burnDescription(tokensPerMinute: 12_400, costPerHour: 32.22, projectedCost: 151.4, bundle: english)
        XCTAssertEqual(priced?.value, "12K tok/min")
        XCTAssertEqual(priced?.detail, "$32.22/h · ≈$151 by reset")
    }

    func testExplanationsSpellOutTheIndicators() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = UsageWindow(utilization: 0.26, resetsAt: now.addingTimeInterval(4 * 3600 + 26 * 60))
        XCTAssertEqual(
            ClaudeUsageRules.ringExplanation(kind: .fiveHour, window: window, now: now, bundle: english),
            "5-hour limit — 26% of the allowance used, resets in 4h 26m. Outer arc: 11% of the window has passed."
        )
        XCTAssertEqual(ClaudeUsageRules.ringExplanation(kind: .sevenDay, window: nil, now: now, bundle: english), "Weekly limit — Anthropic has not reported it yet.")

        var day = try! CCUsageParser.daily(from: Data(#"{"daily":[{"date":"2026-09-05","inputTokens":30267,"outputTokens":312091,"cacheCreationTokens":1707713,"cacheReadTokens":62103462,"totalTokens":64153533,"totalCost":0,"modelBreakdowns":[{"modelName":"claude-fable-5-1","inputTokens":30137,"outputTokens":203469,"cost":0}]}]}"#.utf8)).daily[0]
        XCTAssertEqual(
            ClaudeUsageRules.tokensExplanation(day: day, bundle: english),
            "Tokens today: 64.2M — 30K in (the part not served from cache), 312K out, 63.8M cache (62.1M read + 1.7M written). Claude Code reads most of each prompt from the cache, which is why \"in\" looks small."
        )
        XCTAssertEqual(ClaudeUsageRules.spendExplanation(day: day, bundle: english), "Spend today, as far as ccusage can price it. No price is known for Fable 5.1 — its tokens count as $0.")
        day = try! CCUsageParser.daily(from: Data(#"{"daily":[{"date":"2026-09-05","totalTokens":10,"totalCost":27.68,"modelBreakdowns":[{"modelName":"claude-opus-5","outputTokens":5,"cost":27.68}]}]}"#.utf8)).daily[0]
        XCTAssertEqual(ClaudeUsageRules.spendExplanation(day: day, bundle: english), "Spent today: $27.68, priced by ccusage's offline table.")

        XCTAssertEqual(
            ClaudeUsageRules.paceExplanation(tokensPerMinute: 3279, costPerHour: 32.22, projectedCost: 151, blockEnd: now.addingTimeInterval(2 * 3600), now: now, bundle: english),
            "Current 5-hour block: 3K tok/min, $32.22/h · ≈$151 by reset. Block ends in 2h."
        )
        let shares = [ModelShare(name: "Opus 5", share: 0.74), ModelShare(name: "Fable 5.1", share: 0.26)]
        XCTAssertEqual(ClaudeUsageRules.modelsExplanation(shares: shares, bySpend: true, bundle: english), "Today's work by model, by spend: Opus 5 74%, Fable 5.1 26%.")
        XCTAssertEqual(ClaudeUsageRules.modelsExplanation(shares: [shares[1]], bySpend: false, bundle: english), "All of today's work went through Fable 5.1.")
    }

    func testTokenCompositionAndBlockExplanation() throws {
        let day = try CCUsageParser.daily(from: Data(#"{"daily":[{"date":"2026-09-05","inputTokens":100,"outputTokens":300,"cacheCreationTokens":200,"cacheReadTokens":400,"totalTokens":1000,"totalCost":0}]}"#.utf8)).daily[0]
        let parts = TokenPart.compose(day)
        XCTAssertEqual(parts.map(\.kind), [.output, .input, .cache], "the expensive part leads")
        XCTAssertEqual(parts.map(\.tokens), [300, 100, 600])
        XCTAssertEqual(parts.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(TokenPart.compose(try CCUsageParser.daily(from: Data(#"{"daily":[{"date":"d"}]}"#.utf8)).daily[0]), [])

        let blocks = try CCUsageParser.blocks(from: Data(#"{"blocks":[{"id":"a","startTime":"2026-09-05T06:00:00.000Z","endTime":"2026-09-05T11:00:00.000Z","totalTokens":4000000},{"id":"b","startTime":"2026-09-05T12:00:00.000Z","endTime":"2026-09-05T17:00:00.000Z","isActive":true,"totalTokens":12900000}]}"#.utf8)).blocks
        let text = ClaudeUsageRules.blocksExplanation(blocks: blocks, activeID: "b", bundle: english)
        XCTAssertTrue(text.hasPrefix("Today's 5-hour blocks by tokens: "), text)
        XCTAssertTrue(text.contains("4.0M") && text.contains("12.9M (active)"), text)
        XCTAssertEqual(ClaudeUsageRules.blocksExplanation(blocks: [], activeID: nil, bundle: english), "No 5-hour block has started today.")

        let now = blocks[1].startTime.addingTimeInterval(100 * 60)
        let active = ClaudeUsageRules.blockExplanation(blocks[1], isActive: true, now: now, bundle: english)
        XCTAssertTrue(active.hasPrefix("Active block "), active)
        XCTAssertTrue(active.contains("12.9M tokens so far; 3h 20m left in it."), active)
        let finished = ClaudeUsageRules.blockExplanation(blocks[0], isActive: false, now: now, bundle: english)
        XCTAssertTrue(finished.hasPrefix("Block "), finished)
        XCTAssertTrue(finished.contains("4.0M tokens; last activity at"), finished)
    }

    func testCompactLabelPrefersTheLimit() {
        XCTAssertEqual(ClaudeUsageRules.compactLabel(fiveHour: UsageWindow(utilization: 0.42, resetsAt: nil), todayCost: 9, bundle: english), "42%")
        XCTAssertEqual(ClaudeUsageRules.compactLabel(fiveHour: nil, todayCost: 27.68), "$27.68")
        XCTAssertNil(ClaudeUsageRules.compactLabel(fiveHour: nil, todayCost: nil))
    }

    func testScopedLimitsGetThresholdAlertsToo() {
        let reset = Date(timeIntervalSince1970: 5_000)
        func snapshot(_ fable: Double) -> UsageSnapshot {
            UsageSnapshot(fiveHour: UsageWindow(utilization: 0.1, resetsAt: reset), sevenDay: nil,
                          scopedLimits: [ScopedLimit(name: "Fable", kind: "weekly_scoped", windowKind: .sevenDay, window: UsageWindow(utilization: fable, resetsAt: reset))],
                          fetchedAt: Date())
        }
        let warmed = ThresholdMemory.evaluate(snapshot: snapshot(0.5), thresholds: UsageThresholds(), memory: ThresholdMemory()).memory
        let crossed = ThresholdMemory.evaluate(snapshot: snapshot(0.85), thresholds: UsageThresholds(), memory: warmed)
        XCTAssertEqual(crossed.crossings.map(\.subject), [.scoped(name: "Fable", windowKind: .sevenDay)])
        XCTAssertTrue(ThresholdMemory.evaluate(snapshot: snapshot(0.9), thresholds: UsageThresholds(), memory: crossed.memory).crossings.isEmpty, "announced once per window")
    }

    func testCrossingEventText() {
        let now = Date(timeIntervalSince1970: 0)
        let crossing = ThresholdCrossing(subject: .window(.fiveHour), threshold: 0.8, window: UsageWindow(utilization: 0.82, resetsAt: now.addingTimeInterval(80 * 60)))
        let event = ClaudeUsageRules.crossingEvent(crossing, moduleID: "claude", now: now, bundle: english)
        XCTAssertEqual(event.title, "5-hour limit at 82%")
        XCTAssertEqual(event.detail, "Slow down — resets in 1h 20m")
        XCTAssertEqual(event.moduleID, "claude")
        let critical = ClaudeUsageRules.crossingEvent(ThresholdCrossing(subject: .window(.sevenDay), threshold: 0.95, window: UsageWindow(utilization: 0.96, resetsAt: nil)), moduleID: "claude", now: now, bundle: english)
        XCTAssertEqual(critical.title, "Weekly limit at 96%")
        XCTAssertEqual(critical.detail, "Nearly exhausted")

        let fable = ClaudeUsageRules.crossingEvent(
            ThresholdCrossing(subject: .scoped(name: "Fable", windowKind: .sevenDay), threshold: 0.8, window: UsageWindow(utilization: 0.81, resetsAt: nil)),
            moduleID: "claude", now: now, bundle: english
        )
        XCTAssertEqual(fable.title, "Fable (weekly) limit at 81%", "a model-scoped limit gets its own alert")
    }
}

// MARK: - Watcher

@MainActor
final class ProjectsWatcherTests: XCTestCase {
    func testBatchesChangesIntoOneCallback() async throws {
        let watcher = ProjectsWatcher()
        var batches: [[String]] = []
        watcher.onChange = { batches.append($0.map(\.lastPathComponent)) }
        watcher.simulateChange(["/a/x.jsonl"])
        watcher.simulateChange(["/a/y.jsonl", "/a/x.jsonl"])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(batches, [["x.jsonl", "y.jsonl"]])
    }

    func testReportsSessionLogsWrittenUnderARoot() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString)", isDirectory: true)
        let projects = base.appendingPathComponent("projects", isDirectory: true)
        let project = projects.appendingPathComponent("-Users-x-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let watcher = ProjectsWatcher()
        let changed = expectation(description: "a .jsonl changed")
        var received: [String] = []
        watcher.onChange = { urls in
            guard received.isEmpty else { return }
            received = urls.map(\.lastPathComponent)
            changed.fulfill()
        }
        watcher.start(roots: [projects])
        try await Task.sleep(for: .milliseconds(300))

        try "not a log".write(to: project.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "{\"type\":\"user\"}\n".write(to: project.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        await fulfillment(of: [changed], timeout: 5)
        XCTAssertEqual(received, ["session.jsonl"], "only session logs count")
        watcher.stop()
    }
}
