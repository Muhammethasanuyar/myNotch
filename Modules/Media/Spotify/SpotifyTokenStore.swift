import Foundation
import os

/// File-backed token storage, owner-readable only.
///
/// The Keychain is the right home for these, but with ad-hoc signing every rebuild changes the
/// app's code signature and macOS would ask for keychain access on each launch. The move into the
/// Keychain comes with the Developer ID signature (`docs/PLAN.md` §18); until then the file is
/// created with mode 0600 from the first byte and never passes through a wider-open state.
nonisolated struct SpotifyTokenStore: Sendable {
    let fileURL: URL
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "spotify-library")

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyNotch", isDirectory: true)
            .appendingPathComponent("spotify-oauth.json")
    }

    init(fileURL: URL = SpotifyTokenStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// `nil` when there is no file — the user never connected. A file that exists but cannot be
    /// read or decoded is an error the caller shows, not a silent "disconnected".
    func load() throws -> SpotifyTokens? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(SpotifyTokens.self, from: Data(contentsOf: fileURL))
        } catch {
            throw SpotifyLibraryError.storeUnreadable(String(describing: error))
        }
    }

    /// Writes a 0600 temporary file beside the target and swaps it in, so the tokens are never on
    /// disk with the default permissions, not even for the moment between write and chmod.
    func save(_ tokens: SpotifyTokens) throws {
        let directory = fileURL.deletingLastPathComponent()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(tokens)
        let temporary = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            if manager.fileExists(atPath: fileURL.path) {
                _ = try manager.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: fileURL)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    func clear() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Self.log.error("could not remove the Spotify token file: \(String(describing: error), privacy: .public)")
        }
    }
}
