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

    private let runner: any AppleScriptRunning

    init(runner: any AppleScriptRunning) {
        self.runner = runner
    }

    func fetch() async throws -> MediaState? {
        let output = try await runner.run(Self.fetchScript)
        return Self.parse(output, at: Date())
    }

    func send(_ command: MediaCommand) async throws {
        _ = try await runner.run(Self.script(for: command))
    }

    // MARK: Scripts

    static let fetchScript = """
    tell application "Spotify"
        if player state is stopped then return ""
        set sep to (character id 1)
        return (name of current track) & sep & (artist of current track) & sep & (album of current track) & sep & (id of current track) & sep & (artwork url of current track) & sep & (player state as text) & sep & (duration of current track as text) & sep & (player position as text)
    end tell
    """

    nonisolated static func script(for command: MediaCommand) -> String {
        let body: String
        switch command {
        case .playPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let position): body = "set player position to \(max(0, position))"
        }
        return "tell application \"Spotify\" to \(body)"
    }

    // MARK: Parsing

    /// Turns the fetch script's output into a state. Spotify reports the duration in
    /// **milliseconds** and the position in seconds.
    nonisolated static func parse(_ output: String, at now: Date) -> MediaState? {
        guard let fields = MediaScript.fields(output, expected: 8) else { return nil }
        let title = fields[0]
        guard !title.isEmpty else { return nil }

        let durationMilliseconds = Double(fields[6])
        let duration = durationMilliseconds.map { $0 / 1000 }
        return MediaState(
            providerID: "spotify",
            providerName: "Spotify",
            trackID: fields[3].isEmpty ? "\(fields[1])|\(title)" : fields[3],
            title: title,
            artist: fields[1],
            album: fields[2],
            isPlaying: fields[5] == "playing",
            duration: (duration ?? 0) > 0 ? duration : nil,
            elapsed: Double(fields[7]) ?? 0,
            elapsedAt: now,
            artwork: URL(string: fields[4]).map { MediaArtworkSource.url($0) }
        )
    }
}
