import AppKit
import Foundation

/// Spotify through its official scripting interface. Playback changes arrive as
/// `com.spotify.client.PlaybackStateChanged`; the notification payload is not trusted, the full
/// state is re-read with one script round-trip.
struct SpotifyProvider: MediaProvider {
    let id = "spotify"
    let displayName = "Spotify"
    let bundleIdentifier = "com.spotify.client"
    let changeNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")
    let symbolName = "music.note"
    /// Spotify's dictionary advertises `shuffling` and `repeating` as writable, but the app
    /// silently ignores writes to both (measured 2026-09-04), and `starred` errors with -10000.
    /// Their values still read correctly, so the buttons show the real state without being usable.
    /// Liking goes through the Web API instead, when the user has connected it.
    var capabilities: MediaCapabilities {
        MediaCapabilities(canShuffle: false, canRepeat: false, canFavorite: library.connection == .connected, hasRepeatModes: false)
    }

    var favoriteSupport: MediaFavoriteSupport {
        switch library.connection {
        case .connected:
            return .available
        case .connecting:
            return .needsConnection(hint: "Waiting for Spotify in the browser…")
        case .disconnected:
            return .needsConnection(hint: "Connect Spotify to save tracks (opens the browser once)")
        case .notConfigured:
            return .needsSetup(hint: "Set a Spotify client ID: defaults write com.emre.mynotch spotifyClientID <id> — click to open the developer dashboard")
        }
    }

    private let runner: any AppleScriptRunning
    private let library: SpotifyLibraryClient

    init(runner: any AppleScriptRunning, library: SpotifyLibraryClient) {
        self.runner = runner
        self.library = library
    }

    func fetch() async throws -> MediaState? {
        let start = Date()
        let output = try await runner.run(Self.fetchScript)
        guard var state = Self.parse(output, at: MediaScript.sampleDate(start: start, finish: Date())) else { return nil }
        // The scripting interface cannot say whether a track is saved; the Web API can, once per track.
        if let bare = Self.bareTrackID(state.trackID), let saved = await library.isSaved(trackID: bare) {
            state.isFavorite = saved
        }
        return state
    }

    func send(_ command: MediaCommand) async throws {
        if case .setFavorite(let saved, let trackID) = command {
            guard let bare = Self.bareTrackID(trackID) else { return }
            try await library.setSaved(saved, trackID: bare)
            return
        }
        let script = Self.script(for: command)
        guard !script.isEmpty else { return }
        _ = try await runner.run(script)
    }

    func connectFavorites() {
        switch library.connection {
        case .notConfigured:
            library.refreshConfiguration()
            if library.connection == .notConfigured {
                NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
            } else {
                library.connect()
            }
        case .disconnected:
            library.connect()
        case .connecting, .connected:
            break
        }
    }

    /// `spotify:track:5P2q…` → `5P2q…`. Episodes and local files have no library entry, so `nil`.
    nonisolated static func bareTrackID(_ id: String) -> String? {
        let prefix = "spotify:track:"
        guard id.hasPrefix(prefix) else { return nil }
        let bare = String(id.dropFirst(prefix.count))
        return bare.isEmpty ? nil : bare
    }

    // MARK: Scripts

    static let fetchScript = """
    tell application "Spotify"
        if player state is stopped then return ""
        set sep to (character id 1)
        set shuf to "0"
        if shuffling then set shuf to "1"
        set rept to "0"
        if repeating then set rept to "1"
        return (name of current track) & sep & (artist of current track) & sep & (album of current track) & sep & (id of current track) & sep & (artwork url of current track) & sep & (player state as text) & sep & ((duration of current track) as text) & sep & ((round (player position * 1000)) as text) & sep & shuf & sep & rept
    end tell
    """

    nonisolated static func script(for command: MediaCommand) -> String {
        let body: String
        switch command {
        case .playPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let position): body = "set player position to \(max(0, position))"
        case .toggleShuffle: body = "set shuffling to not shuffling"
        // Spotify has no repeat-one, so the cycle is a plain toggle.
        case .cycleRepeat: body = "set repeating to not repeating"
        case .setFavorite: return ""
        }
        return "tell application \"Spotify\" to \(body)"
    }

    // MARK: Parsing

    /// Turns the fetch script's output into a state.
    ///
    /// Both time fields arrive as **integer milliseconds**: AppleScript renders reals with the
    /// user's decimal separator (a comma in a Turkish locale), which `Double(_:)` would reject, so
    /// the script rounds them to whole milliseconds instead.
    nonisolated static func parse(_ output: String, at now: Date) -> MediaState? {
        guard let fields = MediaScript.fields(output, expected: 10) else { return nil }
        let title = fields[0]
        guard !title.isEmpty else { return nil }

        let duration = MediaScript.milliseconds(fields[6]).map { $0 / 1000 }
        return MediaState(
            providerID: "spotify",
            providerName: "Spotify",
            trackID: fields[3].isEmpty ? "\(fields[1])|\(title)" : fields[3],
            title: title,
            artist: fields[1],
            album: fields[2],
            isPlaying: fields[5] == "playing",
            duration: (duration ?? 0) > 0 ? duration : nil,
            elapsed: (MediaScript.milliseconds(fields[7]) ?? 0) / 1000,
            elapsedAt: now,
            artwork: URL(string: fields[4]).map { MediaArtworkSource.url($0) },
            isShuffling: MediaScript.flag(fields[8]),
            repeatMode: MediaScript.flag(fields[9]) ? .all : .off
        )
    }
}
