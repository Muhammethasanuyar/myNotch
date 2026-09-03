import AppKit
import Foundation
import Observation

/// Whether MyNotch can talk to the user's Spotify library.
nonisolated enum SpotifyConnection: Equatable, Sendable {
    /// No client ID yet: `defaults write com.emre.mynotch spotifyClientID <id>`.
    case notConfigured
    case disconnected
    case connecting
    case connected
}

/// Spotify's own scripting interface cannot save a track (its `starred` property errors), so
/// liking goes through the Web API instead: a PKCE authorization the user completes once in the
/// browser, then `/v1/me/tracks`.
///
/// The user brings their own client ID (Spotify's development mode is per-app and per-user), set
/// with `defaults write com.emre.mynotch spotifyClientID <id>`, and registers
/// `http://127.0.0.1:48219/callback` as the app's redirect URI.
@MainActor
@Observable
final class SpotifyLibraryClient {
    private(set) var connection: SpotifyConnection = .disconnected
    private(set) var lastError: String?

    /// Fired after a connection change so the media controller can re-read the current track.
    var onChange: (@MainActor () -> Void)?

    private let store: SpotifyTokenStore
    private let session: URLSession
    let defaults: UserDefaults
    @ObservationIgnored private var tokens: SpotifyTokens?
    /// Saved-state per track id, so the 2 s poll never turns into 2 s API calls.
    @ObservationIgnored private var savedCache: [String: Bool] = [:]
    /// After a failed lookup the API is left alone for a while instead of being asked every poll.
    @ObservationIgnored private var retryAfter: Date = .distantPast
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    static let clientIDKey = "spotifyClientID"
    static let lookupBackoff: TimeInterval = 30

    var clientID: String? {
        let value = defaults.string(forKey: Self.clientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    init(store: SpotifyTokenStore = SpotifyTokenStore(), session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.store = store
        self.session = session
        self.defaults = defaults
        tokens = store.load()
        connection = tokens != nil ? .connected : (clientID == nil ? .notConfigured : .disconnected)
    }

    // MARK: Connecting

    /// Opens the browser for the user to approve MyNotch, waits for Spotify to redirect back to
    /// the loopback server, then stores the tokens.
    func connect() {
        guard connection != .connecting else { return }
        guard let clientID else {
            connection = .notConfigured
            lastError = "Spotify client ID is not set"
            return
        }
        connection = .connecting
        lastError = nil
        let verifier = SpotifyPKCE.makeVerifier()
        let state = UUID().uuidString

        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Listen before opening the browser so the redirect cannot arrive early.
                async let callback = SpotifyLoopbackServer.awaitCallback()
                NSWorkspace.shared.open(SpotifyPKCE.authorizationURL(clientID: clientID, verifier: verifier, state: state))
                let result = try await callback
                if let error = result.error {
                    throw SpotifyLibraryError.authorizationDenied(error)
                }
                guard result.state == state, let code = result.code else {
                    throw SpotifyLibraryError.stateMismatch
                }
                let payload = try await send(SpotifyPKCE.tokenExchangeRequest(code: code, verifier: verifier, clientID: clientID),
                                             decoding: SpotifyTokens.Payload.self)
                let fresh = try SpotifyTokens(payload: payload, previousRefreshToken: nil)
                try store.save(fresh)
                tokens = fresh
                connection = .connected
            } catch {
                lastError = String(describing: error)
                connection = .disconnected
            }
            onChange?()
        }
    }

    func disconnect() {
        connectTask?.cancel()
        store.clear()
        tokens = nil
        savedCache.removeAll()
        connection = clientID == nil ? .notConfigured : .disconnected
        onChange?()
    }

    /// Re-reads the client ID after the user sets it while the app is running.
    func refreshConfiguration() {
        if connection == .notConfigured, clientID != nil {
            connection = .disconnected
            onChange?()
        }
    }

    // MARK: Library

    /// Whether `trackID` is in the user's library; `nil` when not connected or the call failed.
    func isSaved(trackID: String) async -> Bool? {
        guard connection == .connected else { return nil }
        if let cached = savedCache[trackID] { return cached }
        guard Date() >= retryAfter else { return nil }
        do {
            let flags = try await send(authorized(get: "https://api.spotify.com/v1/me/tracks/contains?ids=\(trackID)"),
                                       decoding: [Bool].self)
            guard let saved = flags.first else { return nil }
            savedCache[trackID] = saved
            return saved
        } catch {
            lastError = String(describing: error)
            retryAfter = Date().addingTimeInterval(Self.lookupBackoff)
            return nil
        }
    }

    func setSaved(_ saved: Bool, trackID: String) async throws {
        guard connection == .connected else { throw SpotifyLibraryError.notConnected }
        var request = try await authorized(get: "https://api.spotify.com/v1/me/tracks?ids=\(trackID)")
        request.httpMethod = saved ? "PUT" : "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyLibraryError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        savedCache[trackID] = saved
    }

    // MARK: Private

    private func authorized(get url: String) async throws -> URLRequest {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    /// The current access token, refreshed first if it is about to expire.
    private func validAccessToken() async throws -> String {
        guard var current = tokens else { throw SpotifyLibraryError.notConnected }
        guard current.isExpired() else { return current.accessToken }
        guard let clientID else { throw SpotifyLibraryError.notConfigured }
        let payload = try await send(SpotifyPKCE.refreshRequest(refreshToken: current.refreshToken, clientID: clientID),
                                     decoding: SpotifyTokens.Payload.self)
        current = try SpotifyTokens(payload: payload, previousRefreshToken: current.refreshToken)
        try store.save(current)
        tokens = current
        return current.accessToken
    }

    private func send<T: Decodable>(_ request: URLRequest, decoding: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyLibraryError.malformedResponse("no HTTP response") }
        if http.statusCode == 401 {
            // The refresh token itself was rejected: the user has to approve again.
            store.clear()
            tokens = nil
            connection = .disconnected
            onChange?()
            throw SpotifyLibraryError.notConnected
        }
        guard (200..<300).contains(http.statusCode) else { throw SpotifyLibraryError.httpStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SpotifyLibraryError.malformedResponse(String(describing: error))
        }
    }
}
