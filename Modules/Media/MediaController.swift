import AppKit
import Observation
import os

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
    /// Players that were running at the last refresh. Kept as state rather than asked per call:
    /// a SwiftUI body runs many times during a morph and each ask walks the process list.
    private(set) var runningPlayerIDs: Set<String> = []

    /// Called after every state change with the previous value, so the module can announce a track change.
    var onStateChange: (@MainActor (MediaState?, MediaState?) -> Void)?

    /// Timed lyrics for the current track; the expanded player scrolls them.
    let lyrics = LyricsService()

    private let providers: [any MediaProvider]
    private let cache = ArtworkCache()
    @ObservationIgnored private var activeProviderID: String?
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "media")
    @ObservationIgnored private var observerTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// How many expanded players are on screen (the notch and the Debug Preview can both show one).
    @ObservationIgnored private var detailViewers = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(providers: [any MediaProvider]) {
        self.providers = providers
    }

    convenience init() {
        let runner = AppleScriptRunner()
        let library = SpotifyLibraryClient()
        self.init(providers: [SpotifyProvider(runner: runner, library: library), AppleMusicProvider(runner: runner)])
        // Once Spotify is connected, re-read the track so the heart reflects the library.
        library.onChange = { [weak self] in self?.refresh() }
    }

    /// How the heart should behave for the active player.
    var favoriteSupport: MediaFavoriteSupport {
        activeProvider?.favoriteSupport ?? .unsupported(reason: "Nothing is playing")
    }

    var activeProvider: (any MediaProvider)? {
        guard let id = state?.providerID ?? activeProviderID else { return nil }
        return providers.first { $0.id == id }
    }

    /// The player the notch speaks for: the one that reported state, or else whichever is running.
    /// A paused Spotify with nothing loaded still owns the media screen.
    var displayProvider: (any MediaProvider)? {
        activeProvider ?? providers.first { runningPlayerIDs.contains($0.id) }
    }

    var hasRunningPlayer: Bool { !runningPlayerIDs.isEmpty }

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
        runningPlayerIDs = []
        updateState(nil)
    }

    /// Notifications carry play/pause and track changes; this repairs what they miss — above all
    /// a seek, which Spotify does not announce at all.
    private func startPolling() {
        guard !observerTasks.isEmpty else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = MediaActivityRules.pollInterval(
                    isPlaying: self?.state?.isPlaying ?? false,
                    detailVisible: (self?.detailViewers ?? 0) > 0
                )
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    /// Called by the expanded player as it appears and disappears. While it is up the playhead is
    /// visible, so the controller re-anchors quickly instead of trusting a minutes-old sample.
    func setDetailVisible(_ visible: Bool) {
        detailViewers = max(0, detailViewers + (visible ? 1 : -1))
        guard !observerTasks.isEmpty else { return }
        // Apply the new cadence immediately, and re-read right away when the player opens.
        startPolling()
        if visible { refresh() }
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
        let running = orderedProviders(preferring: providerID).filter { $0.isRunning() }
        runningPlayerIDs = Set(running.map(\.id))
        var denied = false

        for provider in running {
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
        // The cadence is chosen when the loop goes to sleep, so it has to be recomputed whenever
        // its inputs change. Without this the loop picked "nothing is playing → 60 s" at launch,
        // before the first sample had landed, and then never sped up.
        if previous?.isPlaying != newState?.isPlaying {
            startPolling()
        }
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
            do {
                try await provider.send(command)
            } catch {
                // The refresh below rolls the optimistic UI back; the log says why.
                Self.log.error("\(provider.id, privacy: .public) rejected \(String(describing: command), privacy: .public): \(error)")
            }
            // Give the app a moment to apply it, then read the truth back.
            try? await Task.sleep(for: .milliseconds(350))
            self?.refresh(preferring: provider.id)
        }
    }

    /// What the active player lets us do; the control bar hides or dims what it cannot.
    var capabilities: MediaCapabilities {
        activeProvider?.capabilities ?? MediaCapabilities(canShuffle: false, canRepeat: false, canFavorite: false, hasRepeatModes: false)
    }

    // MARK: Optimistic updates
    //
    // Every command is a ~110 ms round-trip followed by a confirming read, so the button would
    // feel dead without showing the expected result immediately. The next refresh corrects us if
    // the player disagreed.

    func togglePlayPause() {
        guard let current = state else { return }
        updateState(current.togglingPlayback())
        send(.playPause)
    }

    func toggleShuffle() {
        guard var current = state, capabilities.canShuffle else { return }
        current.isShuffling.toggle()
        updateState(current)
        send(.toggleShuffle)
    }

    func cycleRepeat() {
        guard var current = state, capabilities.canRepeat else { return }
        current.repeatMode = current.nextRepeatMode(hasModes: capabilities.hasRepeatModes)
        updateState(current)
        send(.cycleRepeat)
    }

    /// Toggles the favourite when the player allows it; otherwise starts whatever would allow it.
    func toggleFavorite() {
        guard var current = state, let provider = activeProvider else { return }
        switch provider.favoriteSupport {
        case .available:
            let favorite = !current.isFavorite
            current.isFavorite = favorite
            updateState(current)
            send(.setFavorite(favorite, trackID: current.trackID))
        case .needsConnection, .needsSetup:
            provider.connectFavorites()
        case .unsupported:
            break
        }
    }
}
