import XCTest
@testable import MyNotch

/// Fixture lines in the shape Claude Code writes today.
private enum Fixture {
    static func assistant(at stamp: String, session: String = "s1", request: String? = "req-1", message: String = "msg-1", model: String = "claude-fable-5-1",
                          input: Int = 10, output: Int = 20, cacheCreate: Int = 30, cacheRead: Int = 40, sidechain: Bool = false, version: String = "2.1.121", extraUsage: String = "") -> String {
        let requestField = request.map { #","requestId":"\#($0)""# } ?? ""
        return #"{"type":"assistant","cwd":"/Users/x/Projects/dynamic-notch","sessionId":"\#(session)""# + requestField
            + #","version":"\#(version)","isSidechain":\#(sidechain),"timestamp":"\#(stamp)","message":{"id":"\#(message)","model":"\#(model)","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheCreate),"cache_read_input_tokens":\#(cacheRead)\#(extraUsage)}}}"#
    }

    static let user = #"{"type":"user","cwd":"/Users/x/Projects/dynamic-notch","sessionId":"s1","timestamp":"2026-09-06T09:00:00.000Z","message":{"role":"user","content":"hello"}}"#
    static let snapshot = #"{"type":"file-history-snapshot","messageId":"m0","snapshot":{"trackedFileBackups":{},"timestamp":"2026-09-01T00:00:00.000Z"},"isSnapshotUpdate":false}"#
    static let title = #"{"type":"custom-title","sessionId":"s1","customTitle":"Notch hover"}"#
}

final class SessionLogParserTests: XCTestCase {
    private func data(_ lines: [String], trailing: String? = nil) -> Data {
        var text = lines.joined(separator: "\n") + "\n"
        if let trailing { text += trailing }
        return Data(text.utf8)
    }

    func testParsesAssistantTurnsAndSkipsTheRest() {
        let chunk = SessionLogParser.parse(data([Fixture.user, Fixture.snapshot, Fixture.assistant(at: "2026-09-06T09:37:12.345Z")]), fallbackSessionID: "file")
        XCTAssertEqual(chunk.entries.count, 1)
        let entry = chunk.entries[0]
        XCTAssertEqual(entry.sessionID, "s1")
        XCTAssertEqual(entry.requestID, "req-1")
        XCTAssertEqual(entry.messageID, "msg-1")
        XCTAssertEqual(entry.model, "claude-fable-5-1")
        XCTAssertEqual(entry.totalTokens, 100)
        XCTAssertEqual(entry.cacheCreationTokens, 30)
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(entry.timestamp, expected.date(from: "2026-09-06T09:37:12.345Z"), "fractional seconds are kept")
        XCTAssertEqual(chunk.tail.cwd, "/Users/x/Projects/dynamic-notch")
        XCTAssertEqual(chunk.tail.sessionID, "s1")
        XCTAssertEqual(chunk.tail.lastModel, "claude-fable-5-1")
        XCTAssertNil(chunk.tail.customTitle)
    }

    func testConsumesOnlyCompleteLines() {
        let complete = Fixture.assistant(at: "2026-09-06T09:00:00.000Z")
        let bytes = data([complete], trailing: #"{"type":"assistant","message":{"usage":{"input_tokens":"#)
        let chunk = SessionLogParser.parse(bytes, fallbackSessionID: "file")
        XCTAssertEqual(chunk.entries.count, 1)
        XCTAssertEqual(chunk.consumed, complete.utf8.count + 1, "the half-written line waits for the next read")
        XCTAssertEqual(SessionLogParser.parse(Data(), fallbackSessionID: "file").consumed, 0)
    }

    func testCacheCreationObjectWinsOverTheFlatField() {
        let line = Fixture.assistant(at: "2026-09-06T09:00:00.000Z", cacheCreate: 999, extraUsage: #","cache_creation":{"ephemeral_5m_input_tokens":5,"ephemeral_1h_input_tokens":7}"#)
        XCTAssertEqual(SessionLogParser.parse(data([line]), fallbackSessionID: "f").entries[0].cacheCreationTokens, 12)
    }

    func testIterationsAreNotAddedAndSpeedRenamesTheModel() {
        let line = Fixture.assistant(at: "2026-09-06T09:00:00.000Z", extraUsage: #","iterations":[{"input_tokens":1000,"output_tokens":1000}],"speed":"fast""#)
        let entry = SessionLogParser.parse(data([line]), fallbackSessionID: "f").entries[0]
        XCTAssertEqual(entry.totalTokens, 100)
        XCTAssertEqual(entry.model, "claude-fable-5-1-fast")
    }

    func testSyntheticModelCountsTokensButNamesNoModel() {
        let entry = SessionLogParser.parse(data([Fixture.assistant(at: "2026-09-06T09:00:00.000Z", model: "<synthetic>")]), fallbackSessionID: "f").entries[0]
        XCTAssertNil(entry.model)
        XCTAssertEqual(entry.totalTokens, 100)
    }

    func testInvalidLinesAreDroppedWithoutStoppingTheFile() {
        let lines = [
            Fixture.assistant(at: "2026-09-06T09:00:00.000Z", version: "dev"),
            Fixture.assistant(at: "2026-09-06T09:01:00.000Z", session: ""),
            Fixture.assistant(at: "2026-09-06T09:02:00.000Z", request: ""),
            Fixture.assistant(at: "not a date"),
            #"{"type":"assistant","message":{"usage":{"input_tokens":1}}, broken"#,
            Fixture.assistant(at: "2026-09-06T09:05:00.000Z", message: "keep")
        ]
        let chunk = SessionLogParser.parse(data(lines), fallbackSessionID: "f")
        XCTAssertEqual(chunk.entries.map(\.messageID), ["keep"])
    }

    func testMissingSessionFallsBackToTheFileName() {
        let line = #"{"type":"assistant","timestamp":"2026-09-06T09:00:00.000Z","message":{"id":"m","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
        let entry = SessionLogParser.parse(data([line]), fallbackSessionID: "abc-123").entries[0]
        XCTAssertEqual(entry.sessionID, "abc-123")
        XCTAssertNil(entry.requestID)
        XCTAssertEqual(entry.dedupeKey, DedupeKey(messageID: "m", requestID: nil, sessionID: "abc-123"))
    }

    func testCustomTitleReachesTheTail() {
        let chunk = SessionLogParser.parse(data([Fixture.assistant(at: "2026-09-06T09:00:00.000Z"), Fixture.title]), fallbackSessionID: "f")
        XCTAssertEqual(chunk.tail.customTitle, "Notch hover")
    }
}

final class BlockCalculatorTests: XCTestCase {
    private func entry(_ stamp: String, tokens: Int = 100, model: String? = "claude-opus-5", message: String = UUID().uuidString) -> UsageEntry {
        UsageEntry(timestamp: date(stamp), sessionID: "s", requestID: "r-" + message, messageID: message, model: model, isSidechain: false,
                   inputTokens: tokens / 4, outputTokens: tokens / 4, cacheCreationTokens: tokens / 4, cacheReadTokens: tokens / 4, costUSD: nil)
    }

    private func date(_ stamp: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)!
    }

    func testBlocksStartOnTheHourInUTC() {
        let blocks = BlockCalculator.identifySessionBlocks([entry("2026-09-04T09:37:00Z"), entry("2026-09-04T10:10:00Z")])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].startTime, date("2026-09-04T09:00:00Z"))
        XCTAssertEqual(blocks[0].endTime, date("2026-09-04T14:00:00Z"))
        XCTAssertEqual(blocks[0].id, "2026-09-04T09:00:00.000Z")
        XCTAssertEqual(blocks[0].entries.count, 2)
    }

    func testAFullWindowOpensTheNextBlockWithoutAGap() {
        let blocks = BlockCalculator.identifySessionBlocks([entry("2026-09-04T09:00:00Z"), entry("2026-09-04T13:59:00Z"), entry("2026-09-04T14:30:00Z")])
        XCTAssertEqual(blocks.map(\.startTime), [date("2026-09-04T09:00:00Z"), date("2026-09-04T14:00:00Z")])
        XCTAssertFalse(blocks.contains(where: \.isGap))
    }

    func testASilenceLongerThanTheWindowLeavesAGapBlock() {
        let blocks = BlockCalculator.identifySessionBlocks([entry("2026-09-04T00:30:00Z"), entry("2026-09-04T12:05:00Z")])
        XCTAssertEqual(blocks.count, 3)
        XCTAssertTrue(blocks[1].isGap)
        XCTAssertEqual(blocks[1].startTime, date("2026-09-04T05:00:00Z"), "the gap starts where the first window closed")
        XCTAssertEqual(blocks[1].endTime, date("2026-09-04T12:00:00Z"))
        XCTAssertEqual(blocks[1].id, "gap-2026-09-04T05:00:00.000Z")
        XCTAssertEqual(blocks[2].startTime, date("2026-09-04T12:00:00Z"))
    }

    func testActivityNeedsRecentWorkAndAnOpenWindow() {
        let block = BlockCalculator.identifySessionBlocks([entry("2026-09-04T09:00:00Z"), entry("2026-09-04T09:30:00Z")])[0]
        XCTAssertTrue(block.isActive(now: date("2026-09-04T12:00:00Z")))
        XCTAssertFalse(block.isActive(now: date("2026-09-04T14:30:00Z")), "five hours after the last turn it is over")
        XCTAssertFalse(block.isActive(now: date("2026-09-04T14:00:00Z")), "and it never outlives its window")
        XCTAssertFalse(UsageBlock(startTime: block.startTime, endTime: block.endTime, entries: [], isGap: true).isActive(now: date("2026-09-04T09:10:00Z")))
    }

    func testBurnRateSpansFirstToLastTurnAndLeavesCacheOutOfTheIndicator() {
        let block = BlockCalculator.identifySessionBlocks([entry("2026-09-04T09:00:00Z", tokens: 400), entry("2026-09-04T09:10:00Z", tokens: 800)])[0]
        let rate = BlockCalculator.burnRate(block, costUSD: 3.0)
        XCTAssertEqual(rate?.tokensPerMinute, 120, "1200 tokens over 10 minutes")
        XCTAssertEqual(rate?.tokensPerMinuteForIndicator, 60, "input + output only")
        XCTAssertEqual(rate?.costPerHour, 18)
        XCTAssertNil(BlockCalculator.burnRate(BlockCalculator.identifySessionBlocks([entry("2026-09-04T09:00:00Z")])[0], costUSD: nil), "a single turn has no span")
    }

    func testProjectionOnlyForTheRunningBlock() {
        let block = BlockCalculator.identifySessionBlocks([entry("2026-09-04T09:00:00Z", tokens: 400), entry("2026-09-04T09:10:00Z", tokens: 800)])[0]
        let rate = BlockCalculator.burnRate(block, costUSD: 3.0)
        let projection = BlockCalculator.projection(block, burnRate: rate, costUSD: 3.0, now: date("2026-09-04T10:00:00Z"))
        XCTAssertEqual(projection?.remainingMinutes, 240)
        XCTAssertEqual(projection?.totalTokens, 1200 + 120 * 240)
        XCTAssertEqual(projection?.totalCost, 3.0 + 18.0 / 60 * 240)
        XCTAssertNil(BlockCalculator.projection(block, burnRate: rate, costUSD: nil, now: date("2026-09-04T15:00:00Z")))
        XCTAssertNil(BlockCalculator.projection(block, burnRate: rate, costUSD: nil, now: date("2026-09-04T10:00:00Z"))?.totalCost, "no dollars, no dollar projection")
    }
}

final class UsageAggregatorTests: XCTestCase {
    private let istanbul: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    private func date(_ stamp: String) -> Date {
        ISO8601DateFormatter().date(from: stamp)!
    }

    private func entry(_ stamp: String, tokens: Int = 100, model: String? = "claude-opus-5", session: String = "s", request: String? = nil, message: String? = nil, sidechain: Bool = false) -> UsageEntry {
        let id = message ?? UUID().uuidString
        return UsageEntry(timestamp: date(stamp), sessionID: session, requestID: request ?? "r-" + id, messageID: id, model: model, isSidechain: sidechain,
                          inputTokens: tokens / 4, outputTokens: tokens / 4, cacheCreationTokens: tokens / 4, cacheReadTokens: tokens / 4, costUSD: nil)
    }

    func testDedupeKeepsTheBetterCopy() {
        let original = entry("2026-09-06T09:00:00Z", tokens: 400, request: "r1", message: "m1")
        let replay = entry("2026-09-06T09:00:01Z", tokens: 400, request: "r1", message: "m1")
        let smaller = entry("2026-09-06T09:00:02Z", tokens: 40, request: "r1", message: "m1")
        XCTAssertEqual(UsageAggregator.dedupe([smaller, original, replay]).map(\.totalTokens), [400])

        let sidechainCopy = entry("2026-09-06T09:00:03Z", tokens: 4000, request: nil, message: "m1", sidechain: true)
        XCTAssertEqual(UsageAggregator.dedupe([sidechainCopy, original]).map(\.isSidechain), [false], "a sidechain copy of the same message loses even with more tokens")

        let noID = UsageEntry(timestamp: date("2026-09-06T09:00:00Z"), sessionID: "s", requestID: nil, messageID: nil, model: nil, isSidechain: false, inputTokens: 1, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, costUSD: nil)
        XCTAssertEqual(UsageAggregator.dedupe([noID, noID]).count, 2, "without a message id nothing can be called a duplicate")
    }

    func testSubagentTurnsAreRealUsage() {
        let parent = entry("2026-09-06T09:00:00Z", request: "r1", message: "m1")
        let agent = entry("2026-09-06T09:00:30Z", request: "r2", message: "m2", sidechain: true)
        XCTAssertEqual(UsageAggregator.dedupe([parent, agent]).count, 2)
    }

    func testDayGroupingFollowsTheLocalCalendar() {
        // 23:30 in Istanbul on the 5th, 00:30 on the 6th: only the second is "today" at 01:00 local.
        let late = entry("2026-09-05T20:30:00Z", tokens: 400)
        let early = entry("2026-09-05T21:30:00Z", tokens: 800)
        let report = UsageAggregator.report(entries: [late, early], now: date("2026-09-05T22:00:00Z"), calendar: istanbul)
        XCTAssertEqual(report.today?.date, "2026-09-06")
        XCTAssertEqual(report.today?.totalTokens, 800)
        XCTAssertEqual(report.todayBlocks.count, 0, "the block began at 20:00 UTC, still the 5th locally")
        XCTAssertEqual(report.activeBlock?.id, "2026-09-05T20:00:00.000Z", "but the running block is reported wherever it began")
        XCTAssertEqual(report.activeBlock?.totalTokens, 1200)
    }

    func testTodayBlocksSkipGapsAndStayInOrder() {
        // 03:05 opens a block that runs to 08:00; 09:10 is past it (and past a five-hour silence,
        // so a gap sits between); 12:10 still belongs to the 09:00 block.
        let entries = [entry("2026-09-06T09:10:00Z"), entry("2026-09-06T12:10:00Z"), entry("2026-09-06T03:05:00Z")]
        let report = UsageAggregator.report(entries: entries, now: date("2026-09-06T12:30:00Z"), calendar: istanbul)
        XCTAssertEqual(report.todayBlocks.map(\.id), ["2026-09-06T03:00:00.000Z", "2026-09-06T09:00:00.000Z"])
        XCTAssertFalse(report.todayBlocks.contains(where: \.isGap))
        XCTAssertEqual(report.activeBlock?.id, "2026-09-06T09:00:00.000Z")
        XCTAssertEqual(report.activeBlock?.totalTokens, 200)
        XCTAssertEqual(report.costSource, .unavailable)
        XCTAssertEqual(report.today?.totalCost, 0)
    }

    func testModelSplitAndCostAllocation() {
        let opus = entry("2026-09-06T09:00:00Z", tokens: 400, model: "claude-opus-5")
        let fable = entry("2026-09-06T09:05:00Z", tokens: 400, model: "claude-fable-5-1")
        let synthetic = entry("2026-09-06T09:06:00Z", tokens: 40, model: nil)
        var day = CCUsageDay(date: "2026-09-06")
        day.totalCost = 12
        day.modelBreakdowns = [CCUsageDay.ModelBreakdown(modelName: "claude-opus-5", cost: 9), CCUsageDay.ModelBreakdown(modelName: "claude-fable-5-1", cost: 3)]
        let cost = CostTable(day: day, asOf: date("2026-09-06T09:07:00Z"))
        let report = UsageAggregator.report(entries: [opus, fable, synthetic], now: date("2026-09-06T09:10:00Z"), calendar: istanbul, cost: cost)

        XCTAssertEqual(report.today?.totalTokens, 840, "the synthetic turn's tokens count")
        XCTAssertEqual(report.today?.modelBreakdowns.map(\.modelName), ["claude-opus-5", "claude-fable-5-1"], "but it is no model; the split is by cost")
        XCTAssertEqual(report.today?.modelBreakdowns.first?.cost, 9)
        XCTAssertEqual(report.today?.totalCost, 12)
        XCTAssertEqual(report.costSource, .ccusage(asOf: date("2026-09-06T09:07:00Z")))
        XCTAssertEqual(report.activeBlock?.costUSD ?? -1, 12, accuracy: 0.0001, "the block holds all of today's tokens, so all of today's dollars")
        XCTAssertNotNil(report.activeBlock?.burnRate?.costPerHour)
    }
}

final class CostAllocatorTests: XCTestCase {
    private func counts(input: Int = 0, output: Int = 0, write: Int = 0, read: Int = 0) -> CCUsageBlock.TokenCounts {
        CCUsageBlock.TokenCounts(inputTokens: input, outputTokens: output, cacheCreationInputTokens: write, cacheReadInputTokens: read)
    }

    func testBlocksAddUpToTheDay() {
        var day = CCUsageDay(date: "2026-09-06")
        day.totalCost = 10
        day.modelBreakdowns = [CCUsageDay.ModelBreakdown(modelName: "a", cost: 6), CCUsageDay.ModelBreakdown(modelName: "b", cost: 4)]
        let tokens = ["a": counts(input: 1000, output: 100, read: 5000), "b": counts(input: 200, output: 300)]
        let scales = CostAllocator.scales(daily: CostTable(day: day, asOf: Date()), todaysTokensByModel: tokens)
        let total = tokens.reduce(0.0) { $0 + CostAllocator.cost($1.value, model: $1.key, scales: scales) }
        XCTAssertEqual(total, 10, accuracy: 0.0001)
        // Half of model a's weighted tokens cost half its dollars.
        let half = CostAllocator.cost(counts(input: 500, output: 50, read: 2500), model: "a", scales: scales)
        XCTAssertEqual(half, 3, accuracy: 0.0001)
    }

    func testUnpricedModelsAndUnknownTablesCostNothing() {
        let scales = CostAllocator.scales(daily: .unknown, todaysTokensByModel: ["a": counts(input: 10)])
        XCTAssertTrue(scales.isEmpty)
        XCTAssertEqual(CostAllocator.cost(counts(input: 10), model: "a", scales: scales), 0)
        XCTAssertEqual(CostAllocator.cost(counts(input: 10), model: nil, scales: ["a": 1]), 0)
    }
}

final class UsageLedgerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("UsageLedgerTests-\(UUID().uuidString)/projects/-Users-x-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent())
    }

    private func write(_ lines: [String], to name: String = "session.jsonl", trailing: String = "") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + "\n" + trailing).utf8).write(to: url)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func stamp(minutesAgo: Int, now: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    func testWarmStartReadsRecentFilesAndIngestAppendsOnlyNewBytes() async throws {
        let now = Date()
        let url = try write([Fixture.assistant(at: stamp(minutesAgo: 30, now: now), message: "a"), Fixture.assistant(at: stamp(minutesAgo: 20, now: now), message: "b")])
        let ledger = UsageLedger()
        let first = await ledger.warmStart(roots: [root.deletingLastPathComponent()], now: now)
        XCTAssertEqual(first.entries.map(\.messageID), ["a", "b"])
        XCTAssertEqual(first.tail?.sessionID, "s1")
        XCTAssertTrue(first.isAnchored)

        let fourth = Fixture.assistant(at: stamp(minutesAgo: 5, now: now), message: "d")
        let cut = fourth.index(fourth.startIndex, offsetBy: fourth.count / 2)
        try append(Fixture.assistant(at: stamp(minutesAgo: 10, now: now), message: "c") + "\n" + String(fourth[..<cut]), to: url)
        let second = await ledger.ingest([url], now: now)
        XCTAssertEqual(second.entries.map(\.messageID), ["a", "b", "c"], "the half-written line waits")
        XCTAssertGreaterThan(second.bytesRead, first.bytesRead)

        try append(String(fourth[cut...]) + "\n", to: url)
        let third = await ledger.ingest([url], now: now)
        XCTAssertEqual(third.entries.map(\.messageID), ["a", "b", "c", "d"], "the finished line is read exactly once")
    }

    func testATruncatedFileStartsOver() async throws {
        let now = Date()
        let url = try write([Fixture.assistant(at: stamp(minutesAgo: 30, now: now), message: "a"), Fixture.assistant(at: stamp(minutesAgo: 20, now: now), message: "b")])
        let ledger = UsageLedger()
        _ = await ledger.warmStart(roots: [root.deletingLastPathComponent()], now: now)
        try Data((Fixture.assistant(at: stamp(minutesAgo: 1, now: now), message: "z") + "\n").utf8).write(to: url)
        let after = await ledger.ingest([url], now: now)
        XCTAssertEqual(after.entries.map(\.messageID), ["z"])
    }

    func testColdReadStopsAtTheWindowAndDropsOldEntries() async throws {
        let now = Date()
        var lines: [String] = []
        for hoursAgo in stride(from: 80, through: 31, by: -1) {
            lines.append(Fixture.assistant(at: stamp(minutesAgo: hoursAgo * 60, now: now), message: "old-\(hoursAgo)"))
        }
        lines.append(Fixture.assistant(at: stamp(minutesAgo: 60, now: now), message: "recent"))
        _ = try write(lines)
        let ledger = UsageLedger()
        let snapshot = await ledger.warmStart(roots: [root.deletingLastPathComponent()], now: now)
        XCTAssertEqual(snapshot.entries.map(\.messageID), ["recent"], "entries beyond the keep window are gone")
        XCTAssertTrue(snapshot.isAnchored, "a thirty-hour silence anchors the chain")
    }

    func testAContinuousChainReadFromTheStartIsAnchored() async throws {
        let now = Date()
        let lines = (0..<40).map { Fixture.assistant(at: stamp(minutesAgo: 60 * 40 - $0 * 60, now: now), message: "m\($0)") }
        _ = try write(lines)
        let ledger = UsageLedger()
        let snapshot = await ledger.warmStart(roots: [root.deletingLastPathComponent()], now: now)
        XCTAssertTrue(snapshot.isAnchored, "the whole file was read, so the chain is complete")
        XCTAssertGreaterThan(snapshot.entries.count, 0)
    }

    func testOldFilesAreNotOpened() async throws {
        let now = Date()
        let url = try write([Fixture.assistant(at: stamp(minutesAgo: 10, now: now), message: "stale")], to: "old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3 * 86_400)], ofItemAtPath: url.path)
        let ledger = UsageLedger()
        let snapshot = await ledger.warmStart(roots: [root.deletingLastPathComponent()], now: now)
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertEqual(snapshot.bytesRead, 0)
    }
}
