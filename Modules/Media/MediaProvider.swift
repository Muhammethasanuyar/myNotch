import AppKit

/// One media app MyNotch can read and control. Providers own their scripts and parsing; the
/// controller decides which one is active.
///
/// Main-actor because providers may consult main-actor state (Spotify's Web API connection); the
/// work itself still happens off the main thread inside `AppleScriptRunner` and `URLSession`.
@MainActor
protocol MediaProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var bundleIdentifier: String { get }
    /// Distributed notification the app posts when playback changes.
    var changeNotification: Notification.Name { get }
    /// SF Symbol used as the source badge in the expanded view.
    var symbolName: String { get }
    /// What this player lets us do, taken from its scripting dictionary.
    var capabilities: MediaCapabilities { get }
    /// How the favourite button should behave for this player right now.
    var favoriteSupport: MediaFavoriteSupport { get }

    /// Whether the app is up. A requirement, not just an extension, so tests can answer it.
    func isRunning() -> Bool
    /// Current playback, or `nil` when the app is stopped or has nothing loaded.
    func fetch() async throws -> MediaState?
    /// The playhead caught at the instant the player updated it, for lyrics that must not drift;
    /// `nil` when the player is not playing or cannot say.
    func precisePosition() async throws -> PlayheadSample?
    func send(_ command: MediaCommand) async throws
    /// Writes the current artwork somewhere readable, if the app cannot hand out a URL.
    func prepareArtwork(destination: URL) async throws -> Bool
    /// Starts whatever sign-in `favoriteSupport == .needsConnection` refers to.
    func connectFavorites()
}

extension MediaProvider {
    /// Whether the app is up. Checked before every script so we never launch an app by talking to it.
    func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func prepareArtwork(destination: URL) async throws -> Bool { false }
    func connectFavorites() {}
    func precisePosition() async throws -> PlayheadSample? { nil }

    var favoriteSupport: MediaFavoriteSupport {
        capabilities.canFavorite ? .available : .unsupported(reason: "\(displayName) does not let other apps save tracks")
    }
}

/// Field separator used by the fetch scripts: a control character that cannot appear in a title.
nonisolated enum MediaScript {
    static let separator = "\u{01}"

    /// The instant the player's position was actually read.
    ///
    /// The read happens somewhere inside the script round-trip (~110 ms on this machine), so the
    /// midpoint is the best estimate. Stamping the finish time instead would leave the playhead —
    /// and with it the lyrics — running about a tenth of a second behind the music.
    static func sampleDate(start: Date, finish: Date) -> Date {
        start.addingTimeInterval(max(0, finish.timeIntervalSince(start)) / 2)
    }

    /// Reads a boolean the scripts emit as "1" or "0".
    ///
    /// The scripts avoid `as text` for booleans for the same reason they avoid it for numbers: the
    /// output should never depend on the user's language.
    static func flag(_ field: String) -> Bool { field == "1" }

    /// Reads a millisecond field.
    ///
    /// The scripts round every time to a whole millisecond because AppleScript renders reals with
    /// the user's decimal separator — `243,69` in a Turkish locale, which `Double(_:)` rejects.
    /// A separator is still tolerated here in case an app ever returns one.
    static func milliseconds(_ field: String) -> Double? {
        Double(field.replacingOccurrences(of: ",", with: "."))
    }

    /// A script that waits for the player's position to tick and returns the fresh value.
    ///
    /// Players update the position they report in coarse steps, so a single read can be a good
    /// part of a second stale — and the lyrics with it. Polling inside one osascript process every
    /// 20 ms until the value changes catches the update within a few tens of milliseconds. Gives
    /// up after ~1.5 s (paused mid-way, or a player that does not tick) with `-1`.
    static func precisePositionScript(app: String) -> String {
        """
        tell application "\(app)"
            if player state is not playing then return "-1"
            set p0 to (round (player position * 1000))
            set p to p0
            set n to 0
            repeat while p = p0 and n < 60
                delay 0.02
                set p to (round (player position * 1000))
                set n to n + 1
            end repeat
            if p = p0 then return "-1"
            return p as text
        end tell
        """
    }

    /// Between the script observing the tick and us receiving its output: process exit and pipe.
    static let receiptLatency: TimeInterval = 0.015

    /// Reads the precise script's output, `nil` for its `-1` sentinel.
    static func precisePosition(_ output: String, receivedAt: Date) -> PlayheadSample? {
        guard let ms = milliseconds(output), ms >= 0 else { return nil }
        return PlayheadSample(position: ms / 1000, sampledAt: receivedAt.addingTimeInterval(-receiptLatency))
    }

    /// Splits a fetch script's output; `nil` when the app returned nothing or an unexpected shape.
    static func fields(_ output: String, expected: Int) -> [String]? {
        guard !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: separator)
        guard parts.count == expected else { return nil }
        return parts
    }
}
