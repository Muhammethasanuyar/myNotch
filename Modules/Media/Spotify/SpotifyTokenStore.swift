import Foundation

/// File-backed token storage, owner-readable only.
///
/// The Keychain is the right home for these, but with ad-hoc signing every rebuild changes the
/// app's code signature and macOS would ask for keychain access on each launch. Phase 5 moves the
/// tokens into the Keychain once the app is signed with a stable identity.
nonisolated struct SpotifyTokenStore: Sendable {
    let fileURL: URL

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyNotch", isDirectory: true)
            .appendingPathComponent("spotify-oauth.json")
    }

    init(fileURL: URL = SpotifyTokenStore.defaultURL) {
        self.fileURL = fileURL
    }

    func load() -> SpotifyTokens? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    func save(_ tokens: SpotifyTokens) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(tokens)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
