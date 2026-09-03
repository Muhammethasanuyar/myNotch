import AppKit
import Observation

/// Single interface over the media providers: listens for their change notifications, keeps the
/// current state, loads artwork and forwards transport commands.
///
/// Updates are event-driven — a slow poll only repairs missed notifications — and every script
/// round-trip happens off the main thread inside `AppleScriptRunner`.
@MainActor
@Observable
final class MediaController {
    private(set) var state: MediaState?
    private(set) var artwork: MediaArtwork?
    private(set) var permission: MediaPermission = .unknown

    /// Called after every state change with the previous value, so the module can announce a track change.
    var onStateChange: (@MainActor (MediaState?, MediaState?) -> Void)?

    /// Timed lyrics for the current track; the expanded player scrolls them.
    let lyrics = LyricsService()

    private let providers: [any MediaProvider]
    private let cache = ArtworkCache()
    @ObservationIgnored private var activeProviderID: String?
    @ObservationIgnored private var observerTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(providers: [any MediaProvider]) {
        self.providers = providers
    }

    convenience init() {
        let runner = AppleScriptRunner()
        self.init(providers: [SpotifyProvider(runner: runner), AppleMusicProvider(runner: runner)])
    }

    var activeProvider: (any MediaProvider)? {
        guard let id = state?.providerID ?? activeProviderID else { return nil }
        return providers.first { $0.id == id }
    }

    // MARK: Lifecycle

    func start() {
        guard observerTasks.isEmpty else { return }
        for provider in providers {
            let name = provider.changeNotification
            let id = provider.id
            observerTasks.append(Task { [weak self] in
                for await _ in DistributedNotificationCenter.default().notifications(named: name) {
                    guard !Task.isCancelled else { return }
                    self?.refresh(preferring: id)
                }
            })
        }
        startPolling()
        refresh()
    }

    func stop() {
        observerTasks.forEach { $0.cancel() }
        observerTasks.removeAll()
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        lyrics.clear()
        updateState(nil)
    }

    /// Notifications carry the real updates; this is the safety net for missed ones and for
    /// scrubber drift while the expanded view is open.
    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = MediaActivityRules.pollInterval(isPlaying: self?.state?.isPlaying ?? false)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    // MARK: Reading

    /// Re-reads playback state. `preferring` is the provider that just announced a change, so a
    /// second running app cannot steal the notch from the one the user is actually driving.
    func refresh(preferring providerID: String? = nil) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(preferring: providerID)
        }
    }

    private func performRefresh(preferring providerID: String?) async {
        let ordered = orderedProviders(preferring: providerID)
        var denied = false

        for provider in ordered {
            guard provider.isRunning() else { continue }
            do {
                if let state = try await provider.fetch(), state.hasContent {
                    permission = .granted
                    activeProviderID = provider.id
                    updateState(state)
                    await loadArtwork(for: state, provider: provider)
                    return
                }
            } catch AppleScriptError.permissionDenied {
                denied = true
            } catch AppleScriptError.appUnavailable {
                continue
            } catch {
                // A one-off script failure should not wipe the strip; the next event re-reads.
                continue
            }
        }

        if denied {
            permission = .denied
            updateState(nil)
            return
        }
        if permission == .unknown { permission = .granted }
        activeProviderID = nil
        updateState(nil)
    }

    /// The announcing provider first, then the one already active, then the rest.
    private func orderedProviders(preferring providerID: String?) -> [any MediaProvider] {
        let preferred = [providerID, activeProviderID].compactMap { $0 }
        return providers.sorted { lhs, rhs in
            index(of: lhs.id, in: preferred) < index(of: rhs.id, in: preferred)
        }
    }

    private func index(of id: String, in preferred: [String]) -> Int {
        preferred.firstIndex(of: id) ?? preferred.count
    }

    private func updateState(_ newState: MediaState?) {
        guard state != newState else { return }
        let previous = state
        state = newState
        if newState == nil { artwork = nil }
        // Lyrics are per track, so only a new item triggers a lookup — play/pause and scrubbing
        // must never hit the network.
        if previous?.artworkKey != newState?.artworkKey {
            lyrics.load(for: newState)
        }
        onStateChange?(previous, newState)
    }

    private func loadArtwork(for state: MediaState, provider: any MediaProvider) async {
        if let cached = cache.cached(for: state) {
            artwork = cached
            return
        }
        if let loaded = await cache.load(for: state, provider: provider), self.state?.artworkKey == state.artworkKey {
            artwork = loaded
        }
    }

    // MARK: Commands

    func send(_ command: MediaCommand) {
        guard let provider = activeProvider else { return }
        Task { [weak self] in
            try? await provider.send(command)
            // Give the app a moment to apply it, then read the truth back.
            try? await Task.sleep(for: .milliseconds(350))
            self?.refresh(preferring: provider.id)
        }
    }

    /// Optimistic local update so the transport reacts before the round-trip completes.
    func applyOptimisticPlayPause() {
        guard let current = state else { return }
        updateState(MediaState(
            providerID: current.providerID,
            providerName: current.providerName,
            trackID: current.trackID,
            title: current.title,
            artist: current.artist,
            album: current.album,
            isPlaying: !current.isPlaying,
            duration: current.duration,
            elapsed: current.liveElapsed(),
            elapsedAt: Date(),
            artwork: current.artwork
        ))
    }
}
