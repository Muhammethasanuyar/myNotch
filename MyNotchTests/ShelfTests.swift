import XCTest
@testable import MyNotch

final class ShelfRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheShelfIsLiveForTwoMinutesAfterADrop() {
        XCTAssertEqual(ShelfRules.activity(itemCount: 3, lastDropAt: now.addingTimeInterval(-10), now: now), .live)
        XCTAssertEqual(ShelfRules.activity(itemCount: 3, lastDropAt: now.addingTimeInterval(-ShelfRules.liveWindow), now: now), .idle)
        XCTAssertEqual(ShelfRules.activity(itemCount: 0, lastDropAt: now, now: now), .idle, "nothing on it: nothing to show")
        XCTAssertEqual(ShelfRules.activity(itemCount: 3, lastDropAt: nil, now: now), .idle, "a shelf loaded from disk stays quiet")
        XCTAssertEqual(ShelfRules.liveUntil(lastDropAt: now), now.addingTimeInterval(120))
        XCTAssertNil(ShelfRules.liveUntil(lastDropAt: nil))
    }

    func testExpiryFollowsTheKeepIntervalAndZeroMeansForever() {
        let added = now.addingTimeInterval(-90_000)
        XCTAssertTrue(ShelfRules.shouldPurge(addedAt: added, now: now, keepInterval: 86_400))
        XCTAssertFalse(ShelfRules.shouldPurge(addedAt: added, now: now, keepInterval: 172_800))
        XCTAssertFalse(ShelfRules.shouldPurge(addedAt: added, now: now, keepInterval: 0))
        XCTAssertFalse(ShelfRules.shouldPurge(addedAt: added, now: now, keepInterval: -5))
        XCTAssertEqual(ShelfRules.expiry(addedAt: added, keepInterval: 3600), added.addingTimeInterval(3600))
        XCTAssertNil(ShelfRules.expiry(addedAt: added, keepInterval: 0))
    }

    func testUniqueFileNamesCountUpBeforeTheExtension() {
        XCTAssertEqual(ShelfRules.uniqueFileName("report.pdf", existing: []), "report.pdf")
        XCTAssertEqual(ShelfRules.uniqueFileName("report.pdf", existing: ["report.pdf"]), "report 2.pdf")
        XCTAssertEqual(ShelfRules.uniqueFileName("report.pdf", existing: ["report.pdf", "report 2.pdf"]), "report 3.pdf")
        XCTAssertEqual(ShelfRules.uniqueFileName("Makefile", existing: ["Makefile"]), "Makefile 2")
        XCTAssertEqual(ShelfRules.uniqueFileName("archive.tar.gz", existing: ["archive.tar.gz"]), "archive.tar 2.gz")
    }

    func testTheLeadingPartOfTheCardIsAirDrop() {
        XCTAssertEqual(ShelfRules.zone(unitPoint: CGPoint(x: 0.1, y: 0.5)), .airDrop)
        XCTAssertEqual(ShelfRules.zone(unitPoint: CGPoint(x: 0.29, y: 0.9)), .airDrop)
        XCTAssertEqual(ShelfRules.zone(unitPoint: CGPoint(x: 0.3, y: 0.5)), .shelf)
        XCTAssertEqual(ShelfRules.zone(unitPoint: CGPoint(x: 0.9, y: 0.1)), .shelf)
        XCTAssertEqual(ShelfRules.zone(unitPoint: nil), .shelf, "a drop straight onto the housing goes on the shelf")
    }

    func testBadgeAndSizes() {
        XCTAssertEqual(ShelfRules.badgeText(count: 1), "1")
        XCTAssertEqual(ShelfRules.badgeText(count: 9), "9")
        XCTAssertEqual(ShelfRules.badgeText(count: 12), "9+")
        XCTAssertEqual(ShelfRules.formatBytes(1_500_000, locale: Locale(identifier: "en_US")), "1.5 MB")
        XCTAssertEqual(ShelfRules.formatBytes(0, locale: Locale(identifier: "en_US")), "Zero kB")
    }

    func testKeepIntervalsSnapToTheOfferedChoices() {
        XCTAssertEqual(ShelfRules.snappedKeepInterval(86_400), 86_400)
        XCTAssertEqual(ShelfRules.snappedKeepInterval(100_000), 86_400)
        XCTAssertEqual(ShelfRules.snappedKeepInterval(500_000), 604_800)
        XCTAssertEqual(ShelfRules.snappedKeepInterval(0), 0)
        XCTAssertEqual(ShelfRules.snappedKeepInterval(-1), 0)
        XCTAssertEqual(ShelfRules.snappedKeepInterval(1), 3600, "the smallest positive value is an hour")
        let bundle = Bundle(for: ShelfRulesTests.self)
        XCTAssertEqual(ShelfRules.keepIntervalTitle(0, bundle: bundle), "Until removed")
        XCTAssertEqual(ShelfRules.keepIntervalTitle(86_400, bundle: bundle), "1 day")
        XCTAssertEqual(ShelfRules.keepIntervalTitle(604_800, bundle: bundle), "1 week")
        XCTAssertEqual(Set(ShelfRules.keepIntervalChoices.map { ShelfRules.keepIntervalTitle($0, bundle: bundle) }).count, ShelfRules.keepIntervalChoices.count, "every choice has its own title")
    }

    func testEventsNameTheCount() {
        let bundle = Bundle(for: ShelfRulesTests.self)
        XCTAssertEqual(ShelfRules.dropEvent(count: 1, moduleID: "shelf", bundle: bundle).title, "1 file on the shelf")
        XCTAssertEqual(ShelfRules.dropEvent(count: 3, moduleID: "shelf", bundle: bundle).title, "3 files on the shelf")
        XCTAssertEqual(ShelfRules.dropEvent(count: 3, moduleID: "shelf", bundle: bundle).moduleID, "shelf")
        XCTAssertEqual(ShelfRules.airDropEvent(count: 2, moduleID: "shelf", bundle: bundle).title, "Sending 2 files via AirDrop")
        XCTAssertEqual(ShelfRules.airDropEvent(count: 1, moduleID: "shelf", bundle: bundle).symbolName, "dot.radiowaves.right")
    }

    func testItemsSortNewestFirst() {
        let root = URL(fileURLWithPath: "/tmp/shelf")
        let old = ShelfItem(record: ShelfRecord(id: UUID(), fileName: "old.txt", byteCount: 1, addedAt: now.addingTimeInterval(-100), isDirectory: false, hasPreview: false), root: root)
        let new = ShelfItem(record: ShelfRecord(id: UUID(), fileName: "new.txt", byteCount: 1, addedAt: now, isDirectory: false, hasPreview: true), root: root)
        XCTAssertEqual(ShelfRules.sorted([old, new]).map(\.fileName), ["new.txt", "old.txt"])
        XCTAssertEqual(new.fileURL, root.appendingPathComponent(new.id.uuidString, isDirectory: true).appendingPathComponent("new.txt", isDirectory: false))
        XCTAssertEqual(new.previewURL, root.appendingPathComponent(new.id.uuidString, isDirectory: true).appendingPathComponent("preview.png"))
        XCTAssertNil(old.previewURL)
    }
}

final class ShelfStorageTests: XCTestCase {
    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfStorageTests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Shelf", isDirectory: true)
        source = base.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let cleanup = base
        addTeardownBlock { try? FileManager.default.removeItem(at: cleanup) }
    }

    private func writeFile(_ name: String, bytes: Int) throws -> URL {
        let url = source.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    func testCopyInKeepsTheOriginalAndDescribesTheCopy() async throws {
        let storage = ShelfStorage(root: root)
        let original = try writeFile("notes.txt", bytes: 1234)
        let record = try await storage.copyIn(original, existingNames: [])
        XCTAssertEqual(record.fileName, "notes.txt")
        XCTAssertEqual(record.byteCount, 1234)
        XCTAssertFalse(record.isDirectory)
        XCTAssertFalse(record.hasPreview)
        let copy = ShelfPaths.fileURL(root: root, record: record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "the source is copied, never moved")
        XCTAssertEqual(try Data(contentsOf: copy).count, 1234)

        let second = try await storage.copyIn(original, existingNames: [record.fileName])
        XCTAssertEqual(second.fileName, "notes 2.txt", "a second copy of the same name gets a number")
        XCTAssertNotEqual(second.id, record.id)
    }

    func testFoldersAreCopiedWholeAndSizedBySum() async throws {
        let storage = ShelfStorage(root: root)
        let folder = source.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 100).write(to: folder.appendingPathComponent("a.bin"))
        try Data(count: 250).write(to: folder.appendingPathComponent("b.bin"))
        let record = try await storage.copyIn(folder, existingNames: [])
        XCTAssertTrue(record.isDirectory)
        XCTAssertEqual(record.byteCount, 350)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ShelfPaths.fileURL(root: root, record: record).appendingPathComponent("b.bin").path))
    }

    func testTheIndexRoundTripsAndDeletionRemovesTheDirectory() async throws {
        let storage = ShelfStorage(root: root)
        let empty = try await storage.loadIndex()
        XCTAssertEqual(empty, [], "no index yet means an empty shelf")
        let a = try await storage.copyIn(try writeFile("a.txt", bytes: 1), existingNames: [])
        let b = try await storage.copyIn(try writeFile("b.txt", bytes: 2), existingNames: [])
        try await storage.saveIndex([a, b])
        let loaded = try await storage.loadIndex()
        XCTAssertEqual(loaded.map(\.id), [a.id, b.id])
        XCTAssertEqual(loaded.map(\.byteCount), [1, 2])
        XCTAssertEqual(loaded[0].addedAt.timeIntervalSince1970, a.addedAt.timeIntervalSince1970, accuracy: 1, "ISO-8601 keeps whole seconds")

        try await storage.delete(id: a.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ShelfPaths.directory(root: root, id: a.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ShelfPaths.directory(root: root, id: b.id).path))
        try await storage.delete(id: a.id)

        try await storage.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let afterClear = try await storage.loadIndex()
        XCTAssertEqual(afterClear, [])
    }

    func testAMissingSourceIsAnError() async {
        let storage = ShelfStorage(root: root)
        do {
            _ = try await storage.copyIn(source.appendingPathComponent("nope.txt"), existingNames: [])
            XCTFail("expected an error")
        } catch let error as ShelfStorageError {
            XCTAssertEqual(error, .sourceMissing("nope.txt"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testACorruptIndexIsReportedNotSwallowed() async throws {
        let storage = ShelfStorage(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: ShelfPaths.indexURL(root: root))
        do {
            _ = try await storage.loadIndex()
            XCTFail("expected an error")
        } catch let error as ShelfStorageError {
            if case .indexUnreadable = error {} else { XCTFail("wrong error \(error)") }
        }
    }

    func testAPreviewLandsBesideTheCopyWhenQuickLookHasOne() async throws {
        let storage = ShelfStorage(root: root)
        let record = try await storage.copyIn(try writeFile("readme.txt", bytes: 64), existingNames: [])
        let made = await storage.makePreview(for: record)
        // QuickLook may decline inside a test host; when it draws, the file must be there.
        XCTAssertEqual(made, FileManager.default.fileExists(atPath: ShelfPaths.previewURL(root: root, id: record.id).path))
    }
}

@MainActor
final class ShelfStoreTests: XCTestCase {
    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfStoreTests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Shelf", isDirectory: true)
        source = base.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let cleanup = base
        addTeardownBlock { try? FileManager.default.removeItem(at: cleanup) }
    }

    private func writeFile(_ name: String) throws -> URL {
        let url = source.appendingPathComponent(name)
        try Data("hello".utf8).write(to: url)
        return url
    }

    func testAcceptingFilesAddsThemNewestFirstAndPersists() async throws {
        let store = ShelfStore(storage: ShelfStorage(root: root))
        var changes = 0
        store.onChange = { changes += 1 }
        let added = await store.accept([try writeFile("one.txt"), try writeFile("two.txt"), source.appendingPathComponent("missing.txt")])
        XCTAssertEqual(added, 2, "the missing file fails alone")
        XCTAssertEqual(store.items.map(\.fileName), ["two.txt", "one.txt"])
        XCTAssertNotNil(store.lastDropAt)
        XCTAssertNotNil(store.lastError, "the failure is reported, not swallowed")
        XCTAssertEqual(store.totalBytes, 10)
        XCTAssertEqual(changes, 1)

        let reloaded = ShelfStore(storage: ShelfStorage(root: root))
        await reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.fileName), ["two.txt", "one.txt"])
        XCTAssertNil(reloaded.lastDropAt, "a reload is not a drop")
    }

    func testExpiredItemsLeaveOnLoadAndWhenTheIntervalShrinks() async throws {
        let storage = ShelfStorage(root: root)
        let fresh = try await storage.copyIn(try writeFile("fresh.txt"), existingNames: [])
        let stale = ShelfRecord(id: UUID(), fileName: "stale.txt", byteCount: 5, addedAt: Date().addingTimeInterval(-2 * 86_400), isDirectory: false, hasPreview: false)
        try await storage.saveIndex([fresh, stale])

        let store = ShelfStore(storage: storage)
        await store.load()
        XCTAssertEqual(store.items.map(\.fileName), ["fresh.txt"], "two days old is past the default day")

        store.keepInterval = 0
        XCTAssertEqual(store.items.count, 1, "forever keeps everything")
        store.keepInterval = 3600
        XCTAssertEqual(store.items.count, 1, "the fresh copy is younger than an hour")
        let old = ShelfRecord(id: UUID(), fileName: "old.txt", byteCount: 5, addedAt: Date().addingTimeInterval(-7200), isDirectory: false, hasPreview: false)
        try await storage.saveIndex([fresh, old])
        await store.load()
        XCTAssertEqual(store.items.map(\.fileName), ["fresh.txt"])
    }

    func testRemovingAndClearing() async throws {
        let store = ShelfStore(storage: ShelfStorage(root: root))
        await store.accept([try writeFile("a.txt"), try writeFile("b.txt")])
        let first = store.items[0]
        await store.remove(first)
        XCTAssertEqual(store.items.map(\.fileName), ["a.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
        await store.removeAll()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.lastDropAt)
    }
}
