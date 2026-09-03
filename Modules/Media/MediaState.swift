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
    /// Mutable so the views can react to a tap before the round-trip confirms it.
    var isPlaying: Bool
    /// Total length in seconds.
    let duration: TimeInterval?
    /// Playhead at `elapsedAt`, in seconds.
    var elapsed: TimeInterval
    var elapsedAt: Date
    /// Where the artwork can be fetched from: a URL (Spotify) or a file the provider wrote (Music).
    let artwork: MediaArtworkSource?
    var isShuffling: Bool = false
    var repeatMode: MediaRepeatMode = .off
    /// Whether the track is in the user's library. Always `false` where the player cannot say.
    var isFavorite: Bool = false

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

    /// A copy with playback flipped and the playhead frozen where it is now, so a tap on
    /// play/pause shows immediately instead of waiting for the round-trip.
    func togglingPlayback(at now: Date = Date()) -> MediaState {
        var copy = self
        copy.elapsed = liveElapsed(at: now)
        copy.elapsedAt = now
        copy.isPlaying.toggle()
        return copy
    }

    /// The mode the repeat button steps to. `hasModes` players walk off → all → one.
    func nextRepeatMode(hasModes: Bool) -> MediaRepeatMode {
        guard hasModes else { return repeatMode.isOn ? .off : .all }
        switch repeatMode {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    private func clampToDuration(_ value: TimeInterval) -> TimeInterval {
        guard let duration, duration > 0 else { return max(0, value) }
        return min(duration, max(0, value))
    }
}

/// How the player repeats. Spotify only knows on and off; Music also repeats a single track.
nonisolated enum MediaRepeatMode: String, Equatable, Sendable {
    case off
    case all
    case one

    var isOn: Bool { self != .off }
    /// SF Symbol for the repeat button.
    var symbolName: String { self == .one ? "repeat.1" : "repeat" }
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
    case toggleShuffle
    /// Steps through the player's repeat modes; each provider knows its own cycle.
    case cycleRepeat
    /// `trackID` is the player's own identifier (Music ignores it and uses the current track).
    case setFavorite(Bool, trackID: String)
}

/// How liking works for a player right now, so the heart can explain itself.
nonisolated enum MediaFavoriteSupport: Equatable, Sendable {
    /// Tap to toggle.
    case available
    /// Tap to start the sign-in that makes it available.
    case needsConnection(hint: String)
    /// Something must be set up first; the hint says what.
    case needsSetup(hint: String)
    /// The player offers no way at all.
    case unsupported(reason: String)

    var isAvailable: Bool { self == .available }
}

/// What a player lets other apps **change**. Reading is a separate matter: Spotify reports its
/// shuffle and repeat state happily, it just ignores writes to them (measured 2026-09-04 — the
/// command succeeds and nothing happens), and its `starred` property errors outright. So on
/// Spotify those controls are indicators, while Music accepts all three.
nonisolated struct MediaCapabilities: Equatable, Sendable {
    let canShuffle: Bool
    let canRepeat: Bool
    let canFavorite: Bool
    /// Music cycles off → all → one; a player without modes only toggles.
    let hasRepeatModes: Bool
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
