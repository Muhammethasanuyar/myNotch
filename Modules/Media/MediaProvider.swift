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

    /// Splits a fetch script's output; `nil` when the app returned nothing or an unexpected shape.
    static func fields(_ output: String, expected: Int) -> [String]? {
        guard !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: separator)
        guard parts.count == expected else { return nil }
        return parts
    }
}
