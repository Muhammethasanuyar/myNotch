import AppKit
import Observation
import os

/// Whatever the system says is playing — Safari, Chrome, IINA, a podcast app — through the bundled
/// mediaremote-adapter. Off unless the user turns it on; quiet whenever the source is Spotify or
/// Music, which have providers of their own. Pushes changes to the controller as the adapter's
/// `stream` prints them, so there is no polling and no AppleScript.
@MainActor
@Observable
final class GenericNowPlayingProvider: MediaProvider {
    let id = "generic"
    let changeNotification: Notification.Name? = nil
    let symbolName = "waveform"
    /// MediaRemote takes transport, seek and the shuffle/repeat toggles; the true state comes back
    /// on the next diff line, so a toggle can never drift. Likes depend on the player and stay off.
    let capabilities = MediaCapabilities(canShuffle: true, canRepeat: true, canFavorite: false, hasRepeatModes: true)

    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var health: AdapterHealth = .unchecked
    private(set) var isStreaming = false
    private(set) var isEnabled = false

    /// Bundle ids of the AppleScript players; the generic source defers to them.
    let scriptOwners: Set<String>
    let paths: MediaRemoteAdapterProcess.Paths?
    private let healthCheck: AdapterHealthCheck
    @ObservationIgnored private var process: MediaRemoteAdapterProcess?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var payload = AdapterPayload()
    @ObservationIgnored private var ticks: AsyncStream<Void>?
    @ObservationIgnored private var tickContinuation: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private let commands = AdapterCommandQueue()
    /// A crash leaves the perl child behind, and nothing but this app runs that script: one
    /// `pkill` at launch, flag or no flag, and the stream waits for it before starting its own.
    @ObservationIgnored private let orphanSweep: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "mediaremote-adapter")

    init(scriptOwners: Set<String>, bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.scriptOwners = scriptOwners
        paths = MediaRemoteAdapterProcess.Paths.bundled(bundle)
        healthCheck = AdapterHealthCheck(defaults: defaults, artefact: AdapterHealthCheck.artefact(for: paths))
        orphanSweep = paths.map { paths in Task { await MediaRemoteAdapterProcess.killOrphans(scriptPath: paths.script.path) } }
        if paths == nil {
            health = .artefactsMissing
        } else if let cached = healthCheck.cached() {
            health = cached.status
        }
    }

    var displayName: String {
        guard let snapshot else { return L("media.generic.name", "Now Playing") }
        return GenericSourceRules.sourceName(snapshot, runningAppName: { NSRunningApplication(processIdentifier: $0)?.localizedName }, fallback: L("media.generic.name", "Now Playing"))
    }

    var bundleIdentifier: String {
        snapshot?.sourceBundleID ?? ""
    }

    // MARK: Switch

    /// The setting. Turning on runs the health check once per OS/app version, then starts the stream.
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on {
            Task { await ensureHealthyAndStream() }
        } else {
            stopStream()
        }
    }

    /// The app is quitting: the child goes with it. The flag is untouched.
    func shutdown() {
        stopStream()
    }

    /// The "try again" button: a fresh `test`, whatever was remembered.
    func recheckHealth() async {
        guard let paths else { health = .artefactsMissing; return }
        stopStream()
        health = await healthCheck.run(process: MediaRemoteAdapterProcess(paths: paths)).status
        if isEnabled, health == .ok { startStream() }
        tick()
    }

    private func ensureHealthyAndStream() async {
        guard let paths else { health = .artefactsMissing; return }
        if health == .unchecked || health == .timedOut {
            health = await healthCheck.run(process: MediaRemoteAdapterProcess(paths: paths)).status
        }
        guard isEnabled, health == .ok else { tick(); return }
        startStream()
    }

    // MARK: Stream

    private func startStream() {
        guard streamTask == nil, let paths, health == .ok else { return }
        let process = MediaRemoteAdapterProcess(paths: paths)
        self.process = process
        isStopping = false
        isStreaming = true
        let sweep = orphanSweep
        streamTask = Task { [weak self] in
            await sweep?.value
            guard !Task.isCancelled else { return }
            for await line in process.lines(debounceMS: 250, includeArtwork: true) {
                guard let self, !Task.isCancelled else { return }
                switch line {
                case .payload(let data): handle(data)
                case .diagnostic(let message): Self.log.info("adapter: \(message, privacy: .public)")
                case .exited(let code): streamEnded(code)
                }
            }
        }
    }

    private func stopStream() {
        isStopping = true
        streamTask?.cancel()
        streamTask = nil
        process?.terminate()
        process = nil
        isStreaming = false
        snapshot = nil
        payload = AdapterPayload()
        tick()
    }

    private func handle(_ data: Data) {
        do {
            guard let envelope = try AdapterEnvelope.decode(data) else {
                payload = AdapterPayload()
                snapshot = nil
                tick()
                return
            }
            let itemChanged = payload.apply(envelope)
            snapshot = NowPlayingSnapshot(payload: payload)
            if itemChanged, let snapshot {
                Self.log.info("adapter item: \(snapshot.sourceBundleID ?? "?", privacy: .public) pid \(snapshot.processIdentifier, privacy: .public) — \(snapshot.title, privacy: .private)")
            }
            tick()
        } catch {
            Self.log.error("adapter line not understood: \(String(describing: error), privacy: .public)")
        }
    }

    /// A stream that ends on its own is a broken adapter: nothing restarts it, the AppleScript
    /// providers carry on, and the setting shows why.
    private func streamEnded(_ code: Int32) {
        let stopping = isStopping
        streamTask = nil
        process = nil
        isStreaming = false
        snapshot = nil
        payload = AdapterPayload()
        if !stopping, code != 0 {
            health = .broken(exitCode: code)
            _ = healthCheck.record(health)
            Self.log.error("adapter stream exited \(code, privacy: .public); falling back to AppleScript")
        }
        tick()
    }

    private func tick() {
        tickContinuation?.yield(())
    }

    // MARK: MediaProvider

    /// One consumer — the controller — subscribes once.
    func changeTicks() -> AsyncStream<Void>? {
        if ticks == nil {
            ticks = AsyncStream { [weak self] continuation in
                Task { @MainActor in self?.tickContinuation = continuation }
            }
        }
        return ticks
    }

    func isRunning() -> Bool {
        guard isEnabled, health == .ok, isStreaming, let snapshot else { return false }
        return !GenericSourceRules.isOwnedByScriptProvider(snapshot, owned: scriptOwners)
    }

    func fetch() async throws -> MediaState? {
        guard isRunning(), let snapshot else { return nil }
        return snapshot.mediaState(providerID: id, providerName: displayName, now: Date())
    }

    func send(_ command: MediaCommand) async throws {
        guard let process else { return }
        switch command {
        case .seek(let seconds):
            await commands.enqueue(.seek(microseconds: adapterMicroseconds(seconds)), on: process)
        case .setFavorite:
            return
        default:
            guard let remote = MediaRemoteCommand(command) else { return }
            await commands.enqueue(.send(remote), on: process)
        }
    }

    func prepareArtwork(destination: URL) async throws -> Bool {
        guard let base64 = snapshot?.artworkBase64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return false }
        try data.write(to: destination)
        return true
    }
}

/// Every command is a perl process; this runs them one at a time and lets a newer command of the
/// same kind replace one still waiting, so a burst of taps does not pile up children.
actor AdapterCommandQueue {
    private var pending: [MediaRemoteAdapterProcess.Command] = []
    private var isDraining = false

    func enqueue(_ command: MediaRemoteAdapterProcess.Command, on process: MediaRemoteAdapterProcess) async {
        pending.removeAll { Self.kind(of: $0) == Self.kind(of: command) }
        pending.append(command)
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while !pending.isEmpty {
            let next = pending.removeFirst()
            _ = try? await process.run(next, timeout: 10)
        }
    }

    private static func kind(of command: MediaRemoteAdapterProcess.Command) -> String {
        switch command {
        case .get: "get"
        case .stream: "stream"
        case .send(let remote): "send:\(remote.rawValue)"
        case .seek: "seek"
        case .test: "test"
        }
    }
}
