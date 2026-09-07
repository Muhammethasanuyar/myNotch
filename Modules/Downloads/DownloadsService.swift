import AppKit
import Foundation
import Observation
import os

/// Watches the Downloads folder for browsers' in-progress files and turns them into a list of
/// transfers. FSEvents wakes it; a scan runs at most twice a second while something is being
/// written and never otherwise. Reading the folder is what raises the macOS folder permission, so
/// nothing is read until the module is on and `start()` runs.
@MainActor
@Observable
final class DownloadsService {
    enum Access: Equatable, Sendable {
        case unknown
        case granted
        case denied
    }

    private(set) var items: [DownloadItem] = []
    private(set) var access: Access = .unknown
    private(set) var folder: URL
    var keepRecent = 5
    var onChange: (() -> Void)?
    var onCompleted: ((DownloadItem) -> Void)?

    private let watcher = DirectoryWatcher(filter: { path in
        // Sidecars and their would-be destinations: the rename at the end arrives as one batch.
        !(path as NSString).lastPathComponent.hasPrefix(".")
    })
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var lastScan: Date = .distantPast
    @ObservationIgnored private var isStarted = false
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "downloads")

    static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    init(folder: URL = DownloadsService.defaultFolder) {
        self.folder = folder
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        probe()
    }

    func stop() {
        isStarted = false
        watcher.stop()
        scanTask?.cancel()
        scanTask = nil
        items = []
        access = .unknown
        onChange?()
    }

    /// The Setup button: one directory read, which is what shows the system's permission prompt.
    func requestAccess() {
        guard isStarted else { return }
        probe()
    }

    /// Empty means the user's Downloads folder.
    func setFolder(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = trimmed.isEmpty ? Self.defaultFolder : URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
        guard next != folder else { return }
        folder = next
        if isStarted {
            watcher.stop()
            items = []
            probe()
        }
    }

    func open(_ item: DownloadItem) {
        NSWorkspace.shared.open(item.isFinished ? item.destination : item.sidecar.deletingLastPathComponent())
    }

    func revealInFinder(_ item: DownloadItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.isFinished ? item.destination : item.sidecar])
    }

    // MARK: Scanning

    private func probe() {
        do {
            _ = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            access = .granted
        } catch {
            access = .denied
            Self.log.error("downloads folder unreadable: \(String(describing: error), privacy: .public)")
            onChange?()
            return
        }
        watcher.onChange = { [weak self] _ in self?.scheduleScan() }
        watcher.start(roots: [folder])
        scheduleScan(immediately: true)
    }

    private func scheduleScan(immediately: Bool = false) {
        guard scanTask == nil else { return }
        let wait = immediately ? Duration.zero : DownloadsRules.coalesce
        scanTask = Task { [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled, let self else { return }
            await scan()
            scanTask = nil
        }
    }

    private func scan() async {
        let folder = folder
        let now = Date()
        lastScan = now
        let result = await Task.detached(priority: .utility) { Self.readFolder(folder, now: now) }.value
        guard isStarted else { return }
        switch result {
        case .failure(let error):
            access = .denied
            Self.log.error("downloads scan failed: \(String(describing: error), privacy: .public)")
        case .success(let scanned):
            access = .granted
            let merged = DownloadsRules.merge(known: items, scanned: scanned.items, existingDestinations: scanned.files, now: now, keepRecent: keepRecent)
            items = merged.items
            merged.completed.forEach { onCompleted?($0) }
        }
        onChange?()
    }

    nonisolated struct FolderScan: Sendable {
        var items: [DownloadItem] = []
        var files: Set<URL> = []
    }

    /// The folder's top level: sidecars become items, everything else is a possible destination.
    nonisolated static func readFolder(_ folder: URL, now: Date) -> Result<FolderScan, Error> {
        let manager = FileManager()
        do {
            let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey]
            let entries = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            var scan = FolderScan()
            for url in entries {
                guard let kind = DownloadsRules.classify(path: url.path) else {
                    scan.files.insert(url.standardizedFileURL)
                    continue
                }
                scan.items.append(item(for: url, kind: kind, keys: keys, manager: manager, now: now))
            }
            return .success(scan)
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func item(for url: URL, kind: DownloadKind, keys: Set<URLResourceKey>, manager: FileManager, now: Date) -> DownloadItem {
        let values = try? url.resourceValues(forKeys: keys)
        var info: [String: Any]?
        var soFar: Int64 = 0
        var total: Int64?
        var source: URL?
        if kind == .safari {
            let plist = url.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: plist), let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                info = parsed
                let progress = DownloadsRules.safariProgress(parsed)
                soFar = progress.soFar
                total = progress.total
                source = progress.source
            }
            if soFar == 0 {
                // The plist may lag; the bundle's own files say how much has arrived.
                soFar = bundleSize(url, manager: manager)
            }
        } else {
            soFar = Int64(values?.fileSize ?? 0)
        }
        let destination = DownloadsRules.destination(forSidecar: url, kind: kind, info: info)
        return DownloadItem(
            id: url.path,
            kind: kind,
            sidecar: url,
            destination: destination,
            displayName: destination.lastPathComponent,
            bytesSoFar: soFar,
            totalBytes: total,
            sourceURL: source,
            startedAt: values?.creationDate ?? now,
            updatedAt: now,
            isFinished: false
        )
    }

    nonisolated private static func bundleSize(_ url: URL, manager: FileManager) -> Int64 {
        guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator where child.lastPathComponent != "Info.plist" {
            total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
