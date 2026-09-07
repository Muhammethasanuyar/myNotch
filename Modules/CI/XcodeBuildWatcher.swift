import Foundation
import Observation
import os

/// Finished Xcode builds on this Mac, read from the build-log manifests under DerivedData. One
/// FSEvents stream on the DerivedData root, filtered to the manifests before anything reaches
/// Swift; a change re-reads that project's manifest off the main actor.
@MainActor
@Observable
final class XcodeBuildWatcher {
    private(set) var runs: [CIRun] = []
    var onChange: (() -> Void)?

    let root: URL
    private let watcher = DirectoryWatcher(filter: { $0.hasSuffix("/LogStoreManifest.plist") && $0.contains("/Logs/Build/") }, debounce: .milliseconds(500))
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var readTask: Task<Void, Never>?
    private nonisolated static let log = Logger(subsystem: "com.emre.mynotch", category: "ci")

    static var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
    }

    init(root: URL = XcodeBuildWatcher.defaultRoot) {
        self.root = root
    }

    func start() {
        guard !isStarted, FileManager.default.fileExists(atPath: root.path) else { return }
        isStarted = true
        watcher.onChange = { [weak self] urls in self?.reload(urls) }
        watcher.start(roots: [root])
        reload(nil)
    }

    func stop() {
        isStarted = false
        watcher.stop()
        readTask?.cancel()
        readTask = nil
        runs = []
    }

    /// Reads the changed manifests (or every manifest at start) and replaces those projects' runs.
    private func reload(_ changed: [URL]?) {
        let root = root
        readTask?.cancel()
        readTask = Task { [weak self] in
            let manifests: [URL]
            if let changed {
                manifests = changed
            } else {
                manifests = await Task.detached(priority: .utility) { Self.manifests(under: root) }.value
            }
            let parsed = await Task.detached(priority: .utility) { Self.read(manifests) }.value
            guard !Task.isCancelled, let self, isStarted else { return }
            var byProject = Dictionary(grouping: runs) { run -> String in
                if case .xcode(let project) = run.source { return project }
                return ""
            }
            for (project, projectRuns) in parsed { byProject[project] = projectRuns }
            runs = byProject.values.flatMap { $0 }
            onChange?()
        }
    }

    nonisolated static func manifests(under root: URL) -> [URL] {
        let manager = FileManager()
        guard let projects = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return projects.map { $0.appendingPathComponent("Logs/Build/LogStoreManifest.plist") }.filter { manager.fileExists(atPath: $0.path) }
    }

    /// Project folder name → its runs. A manifest that will not decode is logged and skipped.
    nonisolated static func read(_ manifests: [URL]) -> [String: [CIRun]] {
        var result: [String: [CIRun]] = [:]
        for url in manifests {
            let project = Self.projectName(for: url)
            do {
                let manifest = try BuildLogManifest.decode(Data(contentsOf: url))
                result[project] = manifest.runs(project: project)
            } catch {
                Self.log.error("could not read \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
                result[project] = []
            }
        }
        return result
    }

    /// `…/DerivedData/MyNotch-abcdef/Logs/Build/LogStoreManifest.plist` → `MyNotch`.
    nonisolated static func projectName(for manifest: URL) -> String {
        let folder = manifest.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        if let dash = folder.lastIndex(of: "-"), folder[folder.index(after: dash)...].count >= 20 {
            return String(folder[..<dash])
        }
        return folder
    }
}
