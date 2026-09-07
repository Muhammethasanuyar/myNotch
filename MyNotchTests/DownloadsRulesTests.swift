import XCTest
@testable import MyNotch

final class DownloadsRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ name: String, kind: DownloadKind = .chromium, soFar: Int64 = 100, total: Int64? = 1000, started: TimeInterval = -30, updated: TimeInterval = -1, finished: Bool = false) -> DownloadItem {
        let sidecar = URL(fileURLWithPath: "/Users/x/Downloads/\(name).\(kind == .safari ? "download" : "crdownload")")
        return DownloadItem(id: sidecar.path, kind: kind, sidecar: sidecar, destination: URL(fileURLWithPath: "/Users/x/Downloads/\(name)"), displayName: name,
                            bytesSoFar: soFar, totalBytes: total, sourceURL: nil, startedAt: now.addingTimeInterval(started), updatedAt: now.addingTimeInterval(updated), isFinished: finished)
    }

    func testSidecarsAreRecognisedByExtension() {
        XCTAssertEqual(DownloadsRules.classify(path: "/d/Xcode.xip.download"), .safari)
        XCTAssertEqual(DownloadsRules.classify(path: "/d/foo.zip.crdownload"), .chromium)
        XCTAssertEqual(DownloadsRules.classify(path: "/d/foo.iso.part"), .generic)
        XCTAssertEqual(DownloadsRules.classify(path: "/d/Foo.PDF.CRDOWNLOAD"), .chromium, "case does not matter")
        XCTAssertNil(DownloadsRules.classify(path: "/d/report.pdf"))
        XCTAssertNil(DownloadsRules.classify(path: "/d/Downloads"))
    }

    func testDestinationsDropTheExtraExtension() {
        XCTAssertEqual(DownloadsRules.destination(forSidecar: URL(fileURLWithPath: "/d/foo.zip.crdownload"), kind: .chromium, info: nil).path, "/d/foo.zip")
        XCTAssertEqual(DownloadsRules.destination(forSidecar: URL(fileURLWithPath: "/d/Foo.dmg.download"), kind: .safari, info: nil).path, "/d/Foo.dmg")
        XCTAssertEqual(DownloadsRules.destination(forSidecar: URL(fileURLWithPath: "/d/Foo.dmg.download"), kind: .safari, info: ["DownloadEntryPath": "~/Downloads/Foo (1).dmg"]).lastPathComponent, "Foo (1).dmg", "Safari's own path wins when present")
    }

    func testSafariProgressTolerates() {
        let full = DownloadsRules.safariProgress([DownloadsRules.safariBytesKey: 12_400_000, DownloadsRules.safariTotalKey: 38_000_000, DownloadsRules.safariURLKey: "https://example.com/a.dmg"])
        XCTAssertEqual(full.soFar, 12_400_000)
        XCTAssertEqual(full.total, 38_000_000)
        XCTAssertEqual(full.source?.host(), "example.com")
        let partial = DownloadsRules.safariProgress([DownloadsRules.safariBytesKey: 5])
        XCTAssertEqual(partial.soFar, 5)
        XCTAssertNil(partial.total)
        let wrong = DownloadsRules.safariProgress([DownloadsRules.safariBytesKey: "twelve", DownloadsRules.safariTotalKey: 0])
        XCTAssertEqual(wrong.soFar, 0)
        XCTAssertNil(wrong.total, "a zero total is unknown, not done")
        XCTAssertEqual(DownloadsRules.safariProgress([:]).soFar, 0)
    }

    func testProgressAndTexts() {
        let bundle = Bundle(for: DownloadsRulesTests.self)
        let known = item("a.zip", soFar: 620, total: 1000)
        XCTAssertEqual(DownloadsRules.progress(known) ?? -1, 0.62, accuracy: 0.001)
        XCTAssertEqual(DownloadsRules.percentText(known, bundle: bundle), "62%")
        let unknown = item("b.zip", soFar: 620, total: nil)
        XCTAssertNil(DownloadsRules.progress(unknown))
        XCTAssertEqual(DownloadsRules.percentText(unknown, bundle: bundle), "…")
        XCTAssertNil(DownloadsRules.progress(item("c", soFar: 5, total: 0)))
        XCTAssertEqual(DownloadsRules.sizeText(item("d", soFar: 12_400_000, total: 38_000_000), locale: Locale(identifier: "en_US")), "12.4 MB / 38 MB")
        XCTAssertEqual(DownloadsRules.sizeText(item("e", soFar: 12_400_000, total: nil), locale: Locale(identifier: "en_US")), "12.4 MB")
    }

    func testMergeTracksGrowthCompletionAndCancellation() {
        let a = item("a.zip", soFar: 100)
        let b = item("b.zip", soFar: 100, total: nil)
        let known = [a, b]
        // a grew, b vanished with its destination present (finished), c is new.
        let aGrown = item("a.zip", soFar: 500)
        let c = item("c.zip", soFar: 10)
        let result = DownloadsRules.merge(known: known, scanned: [aGrown, c], existingDestinations: [b.destination], now: now, keepRecent: 5)
        XCTAssertEqual(result.completed.map(\.displayName), ["b.zip"])
        XCTAssertTrue(result.completed[0].isFinished)
        XCTAssertEqual(result.items.filter { !$0.isFinished }.map(\.displayName), ["a.zip", "c.zip"])
        XCTAssertEqual(result.items.first { $0.displayName == "a.zip" }?.bytesSoFar, 500)
        XCTAssertEqual(result.items.first { $0.displayName == "a.zip" }?.updatedAt, now, "growth refreshes the timestamp")
        XCTAssertEqual(result.items.first { $0.displayName == "a.zip" }?.startedAt, a.startedAt, "the start is kept")

        // b vanished with no destination: cancelled, nothing to say.
        let cancelled = DownloadsRules.merge(known: [b], scanned: [], existingDestinations: [], now: now, keepRecent: 5)
        XCTAssertTrue(cancelled.completed.isEmpty)
        XCTAssertTrue(cancelled.items.isEmpty)

        // A finished item never completes again and the recent list is capped.
        let finished = (0..<7).map { item("old\($0)", updated: Double(-$0), finished: true) }
        let capped = DownloadsRules.merge(known: finished, scanned: [], existingDestinations: Set(finished.map(\.destination)), now: now, keepRecent: 5)
        XCTAssertTrue(capped.completed.isEmpty)
        XCTAssertEqual(capped.items.count, 5)
        XCTAssertEqual(capped.items.first?.displayName, "old0", "newest first")
    }

    func testActivityIsLiveWhileMovingAndBrieflyAfter() {
        let moving = item("a", updated: -5)
        let stalled = item("b", updated: -120)
        let justDone = item("c", updated: -2, finished: true)
        let longDone = item("d", updated: -60, finished: true)
        XCTAssertEqual(DownloadsRules.activity([moving], now: now), .live)
        XCTAssertEqual(DownloadsRules.activity([stalled], now: now), .idle, "a minute without growth parks the strip")
        XCTAssertEqual(DownloadsRules.activity([justDone], now: now), .live, "the tail after a finish")
        XCTAssertEqual(DownloadsRules.activity([longDone], now: now), .idle)
        XCTAssertEqual(DownloadsRules.activity([], now: now), .idle)
        XCTAssertEqual(DownloadsRules.liveUntil([justDone], now: now), justDone.updatedAt.addingTimeInterval(DownloadsRules.liveTail))
        XCTAssertEqual(DownloadsRules.liveUntil([moving], now: now), moving.updatedAt.addingTimeInterval(DownloadsRules.stallAfter))
        XCTAssertNil(DownloadsRules.liveUntil([longDone, stalled], now: now))
    }

    func testAggregateAndEvent() {
        let bundle = Bundle(for: DownloadsRulesTests.self)
        XCTAssertEqual(DownloadsRules.aggregateProgress([item("a", soFar: 500, total: 1000), item("b", soFar: 250, total: 1000)]) ?? -1, 0.375, accuracy: 0.001)
        XCTAssertEqual(DownloadsRules.aggregateProgress([item("a", soFar: 500, total: 1000), item("b", soFar: 250, total: nil)]) ?? -1, 0.5, accuracy: 0.001, "unknown totals are left out")
        XCTAssertNil(DownloadsRules.aggregateProgress([item("b", soFar: 250, total: nil)]))
        XCTAssertNil(DownloadsRules.aggregateProgress([item("done", finished: true)]), "finished items do not count")
        let event = DownloadsRules.completionEvent(item("Xcode.xip", soFar: 3_000_000_000, total: 3_000_000_000), moduleID: "downloads", bundle: bundle)
        XCTAssertEqual(event.title, "Downloaded: Xcode.xip")
        XCTAssertEqual(event.symbolName, "arrow.down.circle.fill")
        XCTAssertEqual(event.duration, 3)
        XCTAssertNotNil(event.detail)
    }
}
