import AppKit
import Observation
import os

/// The shelf as the card sees it: the items, what a drag is about to hit, the last error. Disk
/// work goes through `ShelfStorage`; only finished models come back here.
@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    private(set) var lastDropAt: Date?
    private(set) var lastError: String?
    /// Where a drag over the open card would land; drawn as a highlight.
    var dropHighlight: ShelfDropZone?
    /// How long a copy is kept; `0` means until removed by hand. Expired items go when the value
    /// changes, when the shelf loads and after every drop — no timer.
    var keepInterval: TimeInterval = ShelfRules.defaultKeepInterval {
        didSet { if keepInterval != oldValue { purgeExpired() } }
    }
    /// Fired after the items changed, for the module's activity.
    @ObservationIgnored var onChange: (() -> Void)?

    let storage: ShelfStorage
    let root: URL
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "shelf")

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.record.byteCount }
    }

    init(storage: ShelfStorage = ShelfStorage()) {
        self.storage = storage
        root = storage.root
    }

    func load() async {
        do {
            let records = try await storage.loadIndex()
            items = ShelfRules.sorted(records.map { ShelfItem(record: $0, root: root) })
            lastError = nil
        } catch {
            report(error)
        }
        purgeExpired()
        onChange?()
    }

    /// Copies each file in; returns how many made it. A failure on one file does not stop the rest.
    @discardableResult
    func accept(_ urls: [URL]) async -> Int {
        var added = 0
        for url in urls {
            do {
                let record = try await storage.copyIn(url, existingNames: Set(items.map(\.fileName)))
                items.insert(ShelfItem(record: record, root: root), at: 0)
                added += 1
                Task { await makePreview(for: record) }
            } catch {
                report(error)
            }
        }
        if added > 0 {
            lastDropAt = Date()
            purgeExpired()
            await save()
        }
        onChange?()
        return added
    }

    func remove(_ item: ShelfItem) async {
        do {
            try await storage.delete(id: item.id)
        } catch {
            report(error)
        }
        items.removeAll { $0.id == item.id }
        await save()
        onChange?()
    }

    func removeAll() async {
        do {
            try await storage.deleteAll()
            lastError = nil
        } catch {
            report(error)
        }
        items = []
        lastDropAt = nil
        await save()
        onChange?()
    }

    /// Drops what has outlived `keepInterval`; the copies go in the background.
    func purgeExpired(now: Date = Date()) {
        let expired = items.filter { ShelfRules.shouldPurge(addedAt: $0.record.addedAt, now: now, keepInterval: keepInterval) }
        guard !expired.isEmpty else { return }
        items.removeAll { item in expired.contains { $0.id == item.id } }
        let storage = storage
        Task {
            for item in expired {
                try? await storage.delete(id: item.id)
            }
            await save()
        }
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.fileURL)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    private func makePreview(for record: ShelfRecord) async {
        guard await storage.makePreview(for: record) else { return }
        guard let index = items.firstIndex(where: { $0.id == record.id }) else { return }
        var updated = items[index].record
        updated.hasPreview = true
        items[index] = ShelfItem(record: updated, root: root)
        await save()
    }

    private func save() async {
        do {
            try await storage.saveIndex(items.map(\.record))
        } catch {
            report(error)
        }
    }

    private func report(_ error: any Error) {
        lastError = String(describing: error)
        Self.log.error("shelf: \(String(describing: error), privacy: .public)")
    }
}
