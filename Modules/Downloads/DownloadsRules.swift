import Foundation

/// Which browser family wrote the sidecar, which decides how progress can be read.
nonisolated enum DownloadKind: Equatable, Sendable {
    /// A `.download` bundle whose `Info.plist` carries bytes so far and the total.
    case safari
    /// A `.crdownload` (Chrome, Edge, Brave…) that grows in place; the total is unknown.
    case chromium
    /// `.part`, `.partial`, `.opdownload` and the like: growing file, total unknown.
    case generic
}

/// One transfer, as the scan last saw it.
nonisolated struct DownloadItem: Equatable, Sendable, Identifiable {
    /// The sidecar's path: stable for the life of the transfer.
    let id: String
    let kind: DownloadKind
    let sidecar: URL
    let destination: URL
    let displayName: String
    let bytesSoFar: Int64
    /// `nil` = indeterminate.
    let totalBytes: Int64?
    let sourceURL: URL?
    let startedAt: Date
    let updatedAt: Date
    let isFinished: Bool
}

/// Pure decisions of the downloads module: what a sidecar is, how far it is, when it is done.
nonisolated enum DownloadsRules {
    static let sidecarExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]
    /// Writes arrive many times a second; the scan runs at most this often.
    static let coalesce: Duration = .milliseconds(500)
    /// The strip stays live this long after the last transfer finished.
    static let liveTail: TimeInterval = 5
    /// A sidecar that has not grown for this long is parked, not live.
    static let stallAfter: TimeInterval = 60
    static let popupDuration: TimeInterval = 3
    /// Safari's `Info.plist` keys — to be confirmed against a live download (docs/manual-tests.md).
    static let safariBytesKey = "DownloadEntryProgressBytesSoFar"
    static let safariTotalKey = "DownloadEntryProgressTotalToLoad"
    static let safariURLKey = "DownloadEntryURL"

    static func classify(path: String) -> DownloadKind? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard sidecarExtensions.contains(ext) else { return nil }
        switch ext {
        case "download": return .safari
        case "crdownload": return .chromium
        default: return .generic
        }
    }

    /// The file the transfer becomes: the sidecar without its extra extension, or the path the
    /// Safari plist names when it does.
    static func destination(forSidecar url: URL, kind: DownloadKind, info: [String: Any]?) -> URL {
        if kind == .safari, let path = info?["DownloadEntryPath"] as? String, !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return url.deletingPathExtension()
    }

    /// Bytes so far, the total and the source from a Safari `Info.plist`; anything missing is `nil`/0.
    static func safariProgress(_ info: [String: Any]) -> (soFar: Int64, total: Int64?, source: URL?) {
        let soFar = (info[safariBytesKey] as? NSNumber)?.int64Value ?? 0
        let total = (info[safariTotalKey] as? NSNumber)?.int64Value
        let source = (info[safariURLKey] as? String).flatMap(URL.init(string:))
        return (max(0, soFar), (total ?? 0) > 0 ? total : nil, source)
    }

    /// 0…1, or `nil` when the total is unknown.
    static func progress(_ item: DownloadItem) -> Double? {
        guard let total = item.totalBytes, total > 0 else { return nil }
        return min(1, max(0, Double(item.bytesSoFar) / Double(total)))
    }

    static func percentText(_ item: DownloadItem, bundle: Bundle = .main) -> String {
        guard let progress = progress(item) else { return "…" }
        return String(localized: "downloads.percent", defaultValue: "\(Int((progress * 100).rounded()))%", bundle: bundle)
    }

    /// "12.4 MB / 38 MB" or just "12.4 MB" when the total is unknown.
    static func sizeText(_ item: DownloadItem, locale: Locale = .current) -> String {
        let soFar = item.bytesSoFar.formatted(.byteCount(style: .file).locale(locale))
        guard let total = item.totalBytes else { return soFar }
        return "\(soFar) / \(total.formatted(.byteCount(style: .file).locale(locale)))"
    }

    /// Folds a fresh scan into the known list. A sidecar that vanished counts as finished only when
    /// its destination now exists; otherwise the download was cancelled and says nothing. Finished
    /// items stay for `keepRecent` entries; a finished item never finishes twice.
    static func merge(known: [DownloadItem], scanned: [DownloadItem], existingDestinations: Set<URL>, now: Date, keepRecent: Int) -> (items: [DownloadItem], completed: [DownloadItem]) {
        let scannedByID = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, $0) })
        var active: [DownloadItem] = []
        var finished: [DownloadItem] = known.filter(\.isFinished)
        var completed: [DownloadItem] = []

        for item in known where !item.isFinished {
            if let fresh = scannedByID[item.id] {
                active.append(DownloadItem(
                    id: item.id, kind: item.kind, sidecar: item.sidecar, destination: fresh.destination, displayName: fresh.displayName,
                    bytesSoFar: fresh.bytesSoFar, totalBytes: fresh.totalBytes ?? item.totalBytes, sourceURL: fresh.sourceURL ?? item.sourceURL,
                    startedAt: item.startedAt, updatedAt: fresh.bytesSoFar != item.bytesSoFar ? now : item.updatedAt, isFinished: false
                ))
            } else if existingDestinations.contains(item.destination.standardizedFileURL) {
                let done = DownloadItem(
                    id: item.id, kind: item.kind, sidecar: item.sidecar, destination: item.destination, displayName: item.displayName,
                    bytesSoFar: item.totalBytes ?? item.bytesSoFar, totalBytes: item.totalBytes ?? item.bytesSoFar, sourceURL: item.sourceURL,
                    startedAt: item.startedAt, updatedAt: now, isFinished: true
                )
                finished.insert(done, at: 0)
                completed.append(done)
            }
            // Gone without a destination: cancelled, dropped silently.
        }
        for fresh in scanned where !known.contains(where: { $0.id == fresh.id }) {
            active.append(fresh)
        }
        active.sort { $0.startedAt > $1.startedAt }
        finished.sort { $0.updatedAt > $1.updatedAt }
        return (active + Array(finished.prefix(max(0, keepRecent))), completed)
    }

    /// Live while a transfer is moving, and for a short tail after the last one finished.
    static func activity(_ items: [DownloadItem], now: Date) -> ModuleActivity {
        let moving = items.contains { !$0.isFinished && now.timeIntervalSince($0.updatedAt) < stallAfter }
        if moving { return .live }
        let recentlyDone = items.contains { $0.isFinished && now.timeIntervalSince($0.updatedAt) < liveTail }
        return recentlyDone ? .live : .idle
    }

    /// When the current live spell ends on its own, or `nil` when nothing is live.
    static func liveUntil(_ items: [DownloadItem], now: Date) -> Date? {
        let ends = items.compactMap { item -> Date? in
            if item.isFinished { return item.updatedAt.addingTimeInterval(liveTail) }
            return item.updatedAt.addingTimeInterval(stallAfter)
        }.filter { $0 > now }
        return ends.max()
    }

    static func completionEvent(_ item: DownloadItem, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        NotchEvent(
            moduleID: moduleID,
            title: String(localized: "downloads.event.finished", defaultValue: "Downloaded: \(item.displayName)", bundle: bundle),
            detail: item.totalBytes.map { $0.formatted(.byteCount(style: .file)) },
            symbolName: "arrow.down.circle.fill",
            duration: popupDuration
        )
    }

    /// One number for the compact ring when several transfers run: bytes over bytes where the
    /// total is known; `nil` when none of them knows its total.
    static func aggregateProgress(_ items: [DownloadItem]) -> Double? {
        let active = items.filter { !$0.isFinished }
        let known = active.filter { ($0.totalBytes ?? 0) > 0 }
        guard !known.isEmpty else { return nil }
        let total = known.reduce(Int64(0)) { $0 + ($1.totalBytes ?? 0) }
        let done = known.reduce(Int64(0)) { $0 + min($1.bytesSoFar, $1.totalBytes ?? 0) }
        return total > 0 ? Double(done) / Double(total) : nil
    }
}
