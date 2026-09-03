import Foundation

/// A snapshot of what a media app is playing. Values come from the provider's AppleScript
/// round-trip; the playhead is extrapolated locally so we never have to poll for it.
nonisolated struct MediaState: Equatable, Sendable {
    let providerID: String
    let providerName: String
    /// Stable identity of the item, used to detect track changes.
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    /// Total length in seconds.
    let duration: TimeInterval?
    /// Playhead at `elapsedAt`, in seconds.
    let elapsed: TimeInterval
    let elapsedAt: Date
    /// Where the artwork can be fetched from: a URL (Spotify) or a file the provider wrote (Music).
    let artwork: MediaArtworkSource?

    /// Identity of the artwork, so it is fetched once per track.
    var artworkKey: String { "\(providerID)|\(trackID)" }

    var hasContent: Bool { !title.isEmpty }

    /// Where the playhead is now: the sampled position plus the wall-clock time since it was taken.
    func liveElapsed(at now: Date = Date()) -> TimeInterval {
        guard isPlaying else { return clampToDuration(elapsed) }
        return clampToDuration(elapsed + max(0, now.timeIntervalSince(elapsedAt)))
    }

    /// 0…1 progress for the scrubber; zero when the duration is unknown.
    func progress(at now: Date = Date()) -> Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, liveElapsed(at: now) / duration))
    }

    private func clampToDuration(_ value: TimeInterval) -> TimeInterval {
        guard let duration, duration > 0 else { return max(0, value) }
        return min(duration, max(0, value))
    }
}

/// Where a track's artwork comes from.
nonisolated enum MediaArtworkSource: Equatable, Sendable {
    /// Spotify hands out an image URL.
    case url(URL)
    /// Music can only be asked to write the raw artwork somewhere.
    case file(String)
}

/// What the expanded view can ask the active app to do.
nonisolated enum MediaCommand: Equatable, Sendable {
    case playPause
    case next
    case previous
    case seek(TimeInterval)
}

/// Whether macOS has let us talk to the media apps yet.
nonisolated enum MediaPermission: Equatable, Sendable {
    case unknown
    case granted
    /// The user denied Automation, or has not answered the prompt yet.
    case denied
}

/// Pure rules that turn media state into module behaviour, kept out of the controller so they can
/// be tested without touching AppleScript.
nonisolated enum MediaActivityRules {
    /// Playing or paused with a loaded track means the module wants the compact strip; nothing
    /// loaded (or no permission) means it stays out of the notch.
    static func activity(for state: MediaState?, permission: MediaPermission) -> ModuleActivity {
        guard permission != .denied, let state, state.hasContent else { return .idle }
        return .live
    }

    /// A popup is worth it when the item actually changed while something is playing. Startup
    /// (`previous == nil`) stays quiet so launching the app does not announce whatever was paused.
    static func shouldAnnounceTrackChange(previous: MediaState?, current: MediaState?) -> Bool {
        guard let current, current.hasContent, current.isPlaying else { return false }
        guard let previous, previous.hasContent else { return false }
        return previous.trackID != current.trackID
    }

    /// Recovery cadence.
    ///
    /// Notifications carry play/pause and track changes, but **Spotify posts nothing when the
    /// position is seeked** (measured 2026-09-04), so a stale playhead can only be repaired by
    /// re-reading. While the expanded player is on screen the playhead and the lyrics are visible,
    /// so it is re-anchored every couple of seconds; otherwise the slow net is enough.
    static func pollInterval(isPlaying: Bool, detailVisible: Bool = false) -> Duration {
        guard isPlaying else { return .seconds(60) }
        return detailVisible ? .seconds(2) : .seconds(15)
    }
}
