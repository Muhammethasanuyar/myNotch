import Foundation

/// Apple Music through its scripting interface. Playback changes arrive as
/// `com.apple.Music.playerInfo`. Unlike Spotify, Music has no artwork URL, so the artwork is
/// written to a file on demand.
struct AppleMusicProvider: MediaProvider {
    let id = "appleMusic"
    let displayName = "Music"
    let bundleIdentifier = "com.apple.Music"
    let changeNotification = Notification.Name("com.apple.Music.playerInfo")
    let symbolName = "music.note.list"

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

    /// Asks Music to write the current artwork to `destination`; `false` when the track has none.
    func prepareArtwork(destination: URL) async throws -> Bool {
        let output = try await runner.run(Self.artworkScript(destination: destination.path))
        return output == "ok"
    }

    // MARK: Scripts

    static let fetchScript = """
    tell application "Music"
        if player state is stopped then return ""
        set sep to (character id 1)
        return (name of current track) & sep & (artist of current track) & sep & (album of current track) & sep & (database ID of current track as text) & sep & (player state as text) & sep & ((round (duration of current track * 1000)) as text) & sep & ((round (player position * 1000)) as text)
    end tell
    """

    /// Music exposes artwork only as raw data, so it is written out and read back as a file.
    nonisolated static func artworkScript(destination: String) -> String {
        """
        tell application "Music"
            if player state is stopped then return ""
            if (count of artworks of current track) is 0 then return ""
            set imageData to raw data of artwork 1 of current track
        end tell
        set target to POSIX file "\(destination)"
        set handle to open for access target with write permission
        set eof handle to 0
        write imageData to handle
        close access handle
        return "ok"
        """
    }

    nonisolated static func script(for command: MediaCommand) -> String {
        let body: String
        switch command {
        case .playPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let position): body = "set player position to \(max(0, position))"
        }
        return "tell application \"Music\" to \(body)"
    }

    // MARK: Parsing

    /// Turns the fetch script's output into a state. Like Spotify's, both time fields arrive as
    /// integer milliseconds so a locale's decimal comma can never reach the parser.
    nonisolated static func parse(_ output: String, at now: Date) -> MediaState? {
        guard let fields = MediaScript.fields(output, expected: 7) else { return nil }
        let title = fields[0]
        guard !title.isEmpty else { return nil }

        let duration = MediaScript.milliseconds(fields[5]).map { $0 / 1000 }
        return MediaState(
            providerID: "appleMusic",
            providerName: "Music",
            trackID: fields[3].isEmpty ? "\(fields[1])|\(title)" : fields[3],
            title: title,
            artist: fields[1],
            album: fields[2],
            isPlaying: fields[4] == "playing",
            duration: (duration ?? 0) > 0 ? duration : nil,
            elapsed: (MediaScript.milliseconds(fields[6]) ?? 0) / 1000,
            elapsedAt: now,
            artwork: nil
        )
    }
}
