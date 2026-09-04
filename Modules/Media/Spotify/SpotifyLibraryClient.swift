import AppKit
import Foundation
import Observation
import os

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
/// browser, then `/v1/me/library`.
///
/// Endpoint note (measured 2026-09-04): the older `/v1/me/tracks` and `/v1/me/tracks/contains`
/// are deprecated and answer a bare 403 "Forbidden" even with the right scopes — not the
/// "Insufficient client scope" a missing scope produces. The replacements take Spotify URIs.
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
    /// Saved-state per URI, so the 2 s poll never turns into 2 s API calls. Entries age out so a
    /// like made in Spotify itself shows up within a minute.
    @ObservationIgnored private var savedCache: [String: (saved: Bool, at: Date)] = [:]
    /// After a failed lookup the API is left alone for a while instead of being asked every poll.
    @ObservationIgnored private var retryAfter: Date = .distantPast
    /// Lookups in flight, so overlapping refreshes share one request.
    @ObservationIgnored private var lookups: [String: Task<Bool?, Never>] = [:]
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    static let clientIDKey = "spotifyClientID"
    static let lookupBackoff: TimeInterval = 30
    static let cacheLifetime: TimeInterval = 60
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "spotify-library")

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

    /// Whether the item is in the user's library; `nil` when not connected or the call failed.
    ///
    /// The request runs in its own task on purpose: the media controller cancels a refresh when the
    /// next one starts, and a cancelled lookup would otherwise count as a failure and silence the
    /// heart for `lookupBackoff`. This way the answer lands in the cache for the next refresh.
    func isSaved(uri: String) async -> Bool? {
        guard connection == .connected else { return nil }
        if let cached = savedCache[uri], Date().timeIntervalSince(cached.at) < Self.cacheLifetime {
            return cached.saved
        }
        if let inFlight = lookups[uri] { return await inFlight.value }
        guard Date() >= retryAfter else { return nil }

        let lookup = Task<Bool?, Never> { [weak self] in
            guard let self else { return nil }
            defer { lookups[uri] = nil }
            do {
                let flags = try await send(authorized(Self.containsURL(uri: uri)), decoding: [Bool].self)
                guard let saved = flags.first else { return nil }
                savedCache[uri] = (saved, Date())
                return saved
            } catch {
                lastError = String(describing: error)
                retryAfter = Date().addingTimeInterval(Self.lookupBackoff)
                Self.log.error("library lookup for \(uri, privacy: .public) failed: \(error)")
                return nil
            }
        }
        lookups[uri] = lookup
        return await lookup.value
    }

    func setSaved(_ saved: Bool, uri: String) async throws {
        guard connection == .connected else { throw SpotifyLibraryError.notConnected }
        var request = try await authorized(Self.libraryURL(uri: uri))
        request.httpMethod = saved ? "PUT" : "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyLibraryError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        savedCache[uri] = (saved, Date())
    }

    // MARK: Requests (pure)

    /// `GET /v1/me/library/contains?uris=…`
    nonisolated static func containsURL(uri: String) -> URL {
        url(path: "/v1/me/library/contains", uri: uri)
    }

    /// `PUT` / `DELETE /v1/me/library?uris=…`
    nonisolated static func libraryURL(uri: String) -> URL {
        url(path: "/v1/me/library", uri: uri)
    }

    private nonisolated static func url(path: String, uri: String) -> URL {
        var components = URLComponents(string: "https://api.spotify.com")!
        components.path = path
        components.queryItems = [URLQueryItem(name: "uris", value: uri)]
        return components.url!
    }

    // MARK: Private

    private func authorized(_ url: URL) async throws -> URLRequest {
        let token = try await validAccessToken()
        var request = URLRequest(url: url)
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
