import CoreServices
import Foundation

// Adapted from https://github.com/stevemcqueenz/claude-notch-tracker (MIT): FSEvents on a set of
// directories with file-level events, a short latency and a debounce that hands over one batch.

/// Watches directories with FSEvents and reports the changed paths that pass `filter`, batched so a
/// burst of writes becomes one callback. The filter runs on the FSEvents queue, so paths nobody
/// asked about never reach the main actor. Nothing runs while no stream is started.
@MainActor
final class DirectoryWatcher {
    /// Delivered on the main actor with the changed paths, at most once per debounce window.
    var onChange: (([URL]) -> Void)?
    private(set) var roots: [URL] = []

    let latency: CFTimeInterval
    let debounce: Duration
    /// File-level events name the changed file; without them a change names its directory.
    let fileEvents: Bool
    private static let queue = DispatchQueue(label: "com.emre.mynotch.fsevents", qos: .utility)

    private var stream: FSEventStreamRef?
    private let relay: Relay
    private var pending: Set<String> = []
    private var debounceTask: Task<Void, Never>?

    /// - Parameter filter: which paths count; runs off the main actor, so keep it pure.
    init(filter: @escaping @Sendable (String) -> Bool = { _ in true }, latency: CFTimeInterval = 0.3, debounce: Duration = .milliseconds(250), fileEvents: Bool = true) {
        self.latency = latency
        self.debounce = debounce
        self.fileEvents = fileEvents
        relay = Relay(filter: filter)
    }

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
        var flags = kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        if fileEvents { flags |= kFSEventStreamCreateFlagFileEvents }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
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

    /// Test seam: feeds paths as if FSEvents had reported them (the filter is not applied).
    func simulateChange(_ paths: [String]) {
        enqueue(paths)
    }

    private func enqueue(_ paths: [String]) {
        pending.formUnion(paths)
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let batch = pending.sorted().map { URL(fileURLWithPath: $0) }
            pending.removeAll()
            onChange?(batch)
        }
    }

    /// Crosses the C boundary; `handler` is set once before the stream starts and read on the
    /// FSEvents queue, so no lock is needed. The filter is immutable.
    private final class Relay: @unchecked Sendable {
        let filter: @Sendable (String) -> Bool
        var handler: (@Sendable ([String]) -> Void)?

        init(filter: @escaping @Sendable (String) -> Bool) {
            self.filter = filter
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
        guard let info, count > 0 else { return }
        let relay = Unmanaged<Relay>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
        let matching = paths.filter(relay.filter)
        if !matching.isEmpty { relay.handler?(matching) }
    }
}
