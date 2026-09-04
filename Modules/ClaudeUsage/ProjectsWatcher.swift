import CoreServices
import Foundation

// Adapted from https://github.com/stevemcqueenz/claude-notch-tracker (MIT): FSEvents on the projects
// directories with file-level events, a short latency and a debounce that hands over one batch.

/// Watches Claude Code's `projects/` directories and reports which session logs changed. This is
/// what makes "Claude is working" appear within seconds instead of at the next poll.
@MainActor
final class ProjectsWatcher {
    /// Delivered on the main actor with the changed `.jsonl` files, at most once per debounce window.
    var onChange: (([URL]) -> Void)?
    private(set) var roots: [URL] = []

    static let latency: CFTimeInterval = 0.3
    static let debounce: Duration = .milliseconds(250)
    private static let queue = DispatchQueue(label: "com.emre.mynotch.fsevents", qos: .utility)

    private var stream: FSEventStreamRef?
    private let relay = Relay()
    private var pending: Set<String> = []
    private var debounceTask: Task<Void, Never>?

    func start(roots: [URL]) {
        stop()
        self.roots = roots
        guard !roots.isEmpty else { return }

        relay.handler = { [weak self] paths in
            Task { @MainActor in self?.enqueue(paths) }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(relay).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            flags
        ) else {
            assertionFailure("FSEventStreamCreate failed for \(roots)")
            return
        }
        FSEventStreamSetDispatchQueue(stream, Self.queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
        pending.removeAll()
    }

    /// Test seam: feeds paths as if FSEvents had reported them.
    func simulateChange(_ paths: [String]) {
        enqueue(paths)
    }

    private func enqueue(_ paths: [String]) {
        pending.formUnion(paths)
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            let batch = pending.sorted().map { URL(fileURLWithPath: $0) }
            pending.removeAll()
            onChange?(batch)
        }
    }

    /// Crosses the C boundary; `handler` is set once before the stream starts and read on the
    /// FSEvents queue, so no lock is needed.
    private final class Relay: @unchecked Sendable {
        var handler: (@Sendable ([String]) -> Void)?
    }

    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
        guard let info, count > 0 else { return }
        let relay = Unmanaged<Relay>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
        let logs = paths.filter { $0.hasSuffix(".jsonl") }
        if !logs.isEmpty { relay.handler?(logs) }
    }
}
