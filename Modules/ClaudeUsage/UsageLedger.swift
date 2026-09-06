// Adapted from https://github.com/stevemcqueenz/claude-notch-tracker (MIT): byte-offset incremental
// reads that stop at the last complete line, and a reset when a file shrinks.

import Foundation
import os

/// What the aggregator gets: every kept entry in time order, plus the newest session's header.
nonisolated struct LedgerSnapshot: Sendable {
    let entries: [UsageEntry]
    let tail: SessionTail?
    /// False when the block chain could not be traced back to a five-hour silence, so the first
    /// block's start may differ from ccusage's.
    let isAnchored: Bool
    let bytesRead: Int
    /// The newest "limit reached" line across every file, if any.
    let quota: QuotaLimitEvent?
}

/// Keeps the recent entries of every session log in memory and reads only what changed.
///
/// Cold start reads each recently modified file backwards in chunks until it reaches entries
/// older than the window; afterwards FSEvents batches arrive and only the bytes appended since
/// the last read are parsed. Dedupe happens in the aggregator over the whole set, so incremental
/// reads never have to remember what they already dropped.
actor UsageLedger {
    struct FileState: Sendable {
        var size: UInt64 = 0
        /// The byte after the last complete line read; the next read starts here.
        var offset: UInt64 = 0
        var entries: [UsageEntry] = []
        var tail = SessionTail()
        var quota: QuotaLimitEvent?
        var readFromStart = false
        var lastSeen: Date
    }

    static let chunkBytes: UInt64 = 2 << 20
    static let perFileCap: UInt64 = 64 << 20
    static let maxEntries = 50_000
    /// Files not modified within this long are not worth opening on a cold start.
    static let horizon: TimeInterval = 36 * 3600
    /// Entries older than this cannot be in today's blocks; they are dropped at each pass.
    static let keepWindow: TimeInterval = 30 * 3600
    /// How many times the cold-start window widens looking for a five-hour silence.
    static let anchorRounds = 3

    private var files: [URL: FileState] = [:]
    private var bytesRead = 0
    private var isAnchored = true
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "usage-ledger")

    /// One spelling per file: `/var/…` and `/private/var/…` name the same log.
    nonisolated static func key(for url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    // MARK: Passes

    /// Reads the recent files under `roots`, widening the window until the block chain is anchored.
    func warmStart(roots: [URL], now: Date) -> LedgerSnapshot {
        let candidates = Self.sessionLogs(under: roots, modifiedAfter: now.addingTimeInterval(-Self.horizon)).map(Self.key(for:))
        var cutoff = Self.cutoff(now: now)
        for round in 0..<Self.anchorRounds {
            for url in candidates where needsReading(url, cutoff: cutoff) {
                files[url] = coldRead(url, cutoff: cutoff, now: now)
            }
            isAnchored = anchor(now: now)
            if isAnchored { break }
            cutoff = cutoff.addingTimeInterval(-Self.keepWindow)
            Self.log.info("block chain not anchored, widening the window (round \(round + 1))")
        }
        prune(now: now)
        return snapshot(now: now)
    }

    /// The files an FSEvents batch named: appended bytes are parsed, a shrunken file starts over.
    func ingest(_ urls: [URL], now: Date) -> LedgerSnapshot {
        for url in urls where url.pathExtension == "jsonl" {
            update(Self.key(for: url), now: now)
        }
        prune(now: now)
        return snapshot(now: now)
    }

    /// After a wake or a long silence: catches files FSEvents did not report.
    func resync(roots: [URL], now: Date) -> LedgerSnapshot {
        let recent = Set(Self.sessionLogs(under: roots, modifiedAfter: now.addingTimeInterval(-Self.horizon)).map(Self.key(for:)))
        for url in recent {
            update(url, now: now)
        }
        for url in files.keys where !recent.contains(url) && !FileManager.default.fileExists(atPath: url.path) {
            files.removeValue(forKey: url)
        }
        prune(now: now)
        return snapshot(now: now)
    }

    func snapshot(now: Date) -> LedgerSnapshot {
        let entries = files.values.flatMap(\.entries).sorted { $0.timestamp < $1.timestamp }
        let tail = files.values.compactMap { state -> (Date, SessionTail)? in
            state.tail.lastTimestamp.map { ($0, state.tail) }
        }.max { $0.0 < $1.0 }?.1
        let quota = files.values.compactMap(\.quota).max { $0.observedAt < $1.observedAt }
        return LedgerSnapshot(entries: entries, tail: tail, isAnchored: isAnchored, bytesRead: bytesRead, quota: quota)
    }

    // MARK: Reading

    private func update(_ url: URL, now: Date) {
        guard let size = Self.fileSize(url) else {
            files.removeValue(forKey: url)
            return
        }
        guard var state = files[url], size >= state.size else {
            // New to us, or truncated: whatever we held about it is stale.
            files[url] = coldRead(url, cutoff: Self.cutoff(now: now), now: now)
            return
        }
        if size > state.offset {
            let data = Self.read(url, from: state.offset, to: size)
            bytesRead += data.count
            let chunk = SessionLogParser.parse(data, fallbackSessionID: Self.sessionID(for: url))
            state.offset += UInt64(chunk.consumed)
            state.entries.append(contentsOf: chunk.entries)
            state.tail = Self.merge(older: state.tail, newer: chunk.tail)
            state.quota = Self.newer(state.quota, chunk.quota)
        }
        state.size = size
        state.lastSeen = now
        files[url] = state
    }

    /// A file is worth (re)reading when it is unknown, or was cut before `cutoff` without reaching its start.
    private func needsReading(_ url: URL, cutoff: Date) -> Bool {
        guard let state = files[url] else { return true }
        guard !state.readFromStart, let earliest = state.entries.first?.timestamp else { return false }
        return earliest >= cutoff
    }

    /// Reads a file backwards in chunks until it holds entries older than `cutoff`, reaches the
    /// start, or hits the per-file cap. Lines cut by a chunk boundary are carried to the next chunk.
    private func coldRead(_ url: URL, cutoff: Date, now: Date) -> FileState {
        var state = FileState(lastSeen: now)
        guard let size = Self.fileSize(url) else { return state }
        state.size = size
        let sessionID = Self.sessionID(for: url)
        var end = size
        var carry = Data()
        var chunks: [LogChunk] = []
        var read: UInt64 = 0
        var offsetKnown = false

        while end > 0, read < Self.perFileCap {
            let start = end > Self.chunkBytes ? end - Self.chunkBytes : 0
            var data = Self.read(url, from: start, to: end)
            read += UInt64(data.count)
            data.append(carry)
            if !offsetKnown {
                // The next incremental read resumes after the last newline in the file.
                let trailing = data.lastIndex(of: 0x0A).map { data.count - $0 - 1 } ?? data.count
                state.offset = size - UInt64(trailing)
                offsetKnown = true
            }
            let lines: Data
            if start == 0 {
                lines = data
                state.readFromStart = true
            } else if let newline = data.firstIndex(of: 0x0A) {
                carry = Data(data[data.startIndex..<newline])
                lines = Data(data[(newline + 1)...])
            } else {
                // A line longer than a chunk: keep everything and read on.
                carry = data
                end = start
                continue
            }
            let chunk = SessionLogParser.parse(lines, fallbackSessionID: sessionID)
            chunks.append(chunk)
            end = start
            if let earliest = chunk.entries.first?.timestamp, earliest < cutoff { break }
        }
        bytesRead += Int(read)
        for chunk in chunks.reversed() {
            state.entries.append(contentsOf: chunk.entries)
            state.tail = Self.merge(older: state.tail, newer: chunk.tail)
            state.quota = Self.newer(state.quota, chunk.quota)
        }
        return state
    }

    // MARK: Housekeeping

    /// True when a five-hour silence separates what we keep from whatever came before today, or
    /// when every file was read from its first line; entries before that silence are dropped.
    private func anchor(now: Date) -> Bool {
        let entries = files.values.flatMap(\.entries).sorted { $0.timestamp < $1.timestamp }
        let todayStart = Calendar.current.startOfDay(for: now)
        var anchorDate: Date?
        for (previous, next) in zip(entries, entries.dropFirst()) where next.timestamp <= todayStart {
            if next.timestamp.timeIntervalSince(previous.timestamp) > BlockCalculator.sessionDuration {
                anchorDate = next.timestamp
            }
        }
        if let anchorDate {
            for (url, var state) in files {
                state.entries.removeAll { $0.timestamp < anchorDate }
                files[url] = state
            }
            return true
        }
        return files.values.allSatisfy { $0.readFromStart || $0.entries.isEmpty }
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.keepWindow)
        for (url, var state) in files {
            state.entries.removeAll { $0.timestamp < cutoff }
            if state.entries.isEmpty, now.timeIntervalSince(state.lastSeen) > 48 * 3600 {
                files.removeValue(forKey: url)
            } else {
                files[url] = state
            }
        }
        var total = files.values.reduce(0) { $0 + $1.entries.count }
        while total > Self.maxEntries {
            // Drop the oldest file's oldest entries first; a day this big is not one the card can draw anyway.
            guard let (url, state) = files.min(by: { ($0.value.entries.first?.timestamp ?? .distantFuture) < ($1.value.entries.first?.timestamp ?? .distantFuture) }) else { break }
            var trimmed = state
            let drop = min(trimmed.entries.count, total - Self.maxEntries)
            trimmed.entries.removeFirst(drop)
            files[url] = trimmed
            total -= drop
        }
    }

    // MARK: Pure helpers

    /// Nothing before this can be part of today's blocks: eight hours before midnight covers a
    /// block that began the evening before, and thirty hours covers a long day.
    nonisolated static func cutoff(now: Date, calendar: Calendar = .current) -> Date {
        min(calendar.startOfDay(for: now).addingTimeInterval(-8 * 3600), now.addingTimeInterval(-keepWindow))
    }

    nonisolated static func sessionID(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The more recently observed of two "limit reached" lines.
    nonisolated static func newer(_ current: QuotaLimitEvent?, _ candidate: QuotaLimitEvent?) -> QuotaLimitEvent? {
        guard let candidate else { return current }
        guard let current, current.observedAt > candidate.observedAt else { return candidate }
        return current
    }

    /// Later lines win, but a field the newer stretch lacks keeps its older value.
    nonisolated static func merge(older: SessionTail, newer: SessionTail) -> SessionTail {
        var tail = older
        if let cwd = newer.cwd { tail.cwd = cwd }
        if let session = newer.sessionID { tail.sessionID = session }
        if let stamp = newer.lastTimestamp { tail.lastTimestamp = stamp }
        if let model = newer.lastModel { tail.lastModel = model }
        if let title = newer.customTitle { tail.customTitle = title }
        return tail
    }

    nonisolated static func sessionLogs(under roots: [URL], modifiedAfter: Date) -> [URL] {
        var found: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true, let modified = values.contentModificationDate, modified >= modifiedAfter else { continue }
                found.append(url)
            }
        }
        return found
    }

    nonisolated static func fileSize(_ url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64)
            ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int).map(UInt64.init)
    }

    nonisolated static func read(_ url: URL, from start: UInt64, to end: UInt64) -> Data {
        guard end > start, let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: start)) != nil else { return Data() }
        return (try? handle.read(upToCount: Int(end - start))) ?? Data()
    }
}
