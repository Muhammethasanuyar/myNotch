import AppKit

/// One media app MyNotch can read and control. Providers are stateless: they own their scripts and
/// parsing, and the controller decides which one is active.
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

    /// Current playback, or `nil` when the app is stopped or has nothing loaded.
    func fetch() async throws -> MediaState?
    func send(_ command: MediaCommand) async throws
    /// Writes the current artwork somewhere readable, if the app cannot hand out a URL.
    func prepareArtwork(destination: URL) async throws -> Bool
}

extension MediaProvider {
    /// Whether the app is up. Checked before every script so we never launch an app by talking to it.
    @MainActor
    func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func prepareArtwork(destination: URL) async throws -> Bool { false }
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

    /// Splits a fetch script's output; `nil` when the app returned nothing or an unexpected shape.
    static func fields(_ output: String, expected: Int) -> [String]? {
        guard !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: separator)
        guard parts.count == expected else { return nil }
        return parts
    }
}
