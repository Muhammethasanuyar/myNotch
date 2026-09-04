import XCTest
@testable import MyNotch

final class SpotifyLibraryTests: XCTestCase {
    // MARK: PKCE

    func testVerifierUsesTheUnreservedSetAndIsUnique() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let first = SpotifyPKCE.makeVerifier()
        let second = SpotifyPKCE.makeVerifier()
        XCTAssertEqual(first.count, 64)
        XCTAssertTrue(first.allSatisfy(allowed.contains))
        XCTAssertNotEqual(first, second)
    }

    func testChallengeMatchesTheRFC7636Example() {
        // RFC 7636 appendix B.
        XCTAssertEqual(
            SpotifyPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testAuthorizationURLCarriesEveryParameter() throws {
        let url = SpotifyPKCE.authorizationURL(clientID: "abc", verifier: "verifier", state: "s1")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "accounts.spotify.com")
        XCTAssertEqual(components.path, "/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], "abc")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:48219/callback")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["code_challenge"], SpotifyPKCE.challenge(for: "verifier"))
        XCTAssertEqual(items["scope"], "user-library-read user-library-modify")
        XCTAssertEqual(items["state"], "s1")
    }

    func testTokenExchangeRequestIsAFormPost() throws {
        let request = SpotifyPKCE.tokenExchangeRequest(code: "c+d/e", verifier: "ver", clientID: "id")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, SpotifyPKCE.tokenEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let fields = form(body)
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        XCTAssertEqual(fields["code"], "c+d/e")
        XCTAssertEqual(fields["code_verifier"], "ver")
        XCTAssertEqual(fields["client_id"], "id")
        XCTAssertEqual(fields["redirect_uri"], SpotifyPKCE.redirectURI)
        // A bare `+` would be read back as a space by any form parser.
        XCTAssertFalse(body.contains("+"))
    }

    func testRefreshRequestUsesTheRefreshGrant() throws {
        let request = SpotifyPKCE.refreshRequest(refreshToken: "r1", clientID: "id")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(form(body), ["grant_type": "refresh_token", "refresh_token": "r1", "client_id": "id"])
    }

    func testCallbackParsesCodeAndState() {
        let callback = SpotifyPKCE.callback(fromRequestLine: "GET /callback?code=AQx-y_z&state=s1 HTTP/1.1")
        XCTAssertEqual(callback, SpotifyPKCE.Callback(code: "AQx-y_z", state: "s1", error: nil))
    }

    func testCallbackParsesADenial() {
        let callback = SpotifyPKCE.callback(fromRequestLine: "GET /callback?error=access_denied&state=s1 HTTP/1.1")
        XCTAssertEqual(callback, SpotifyPKCE.Callback(code: nil, state: "s1", error: "access_denied"))
    }

    func testCallbackIgnoresOtherRequests() {
        XCTAssertNil(SpotifyPKCE.callback(fromRequestLine: "GET /favicon.ico HTTP/1.1"))
        XCTAssertNil(SpotifyPKCE.callback(fromRequestLine: "POST /callback?code=x HTTP/1.1"))
        XCTAssertNil(SpotifyPKCE.callback(fromRequestLine: ""))
    }

    // MARK: Tokens

    func testTokensRotateTheRefreshTokenWhenThePayloadCarriesOne() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let payload = SpotifyTokens.Payload(access_token: "a2", refresh_token: "r2", expires_in: 3600)
        let tokens = try SpotifyTokens(payload: payload, previousRefreshToken: "r1", now: now)
        XCTAssertEqual(tokens, SpotifyTokens(accessToken: "a2", refreshToken: "r2", expiresAt: now.addingTimeInterval(3600)))
    }

    func testTokensKeepThePreviousRefreshTokenWhenThePayloadOmitsIt() throws {
        let payload = SpotifyTokens.Payload(access_token: "a2", refresh_token: nil, expires_in: 60)
        XCTAssertEqual(try SpotifyTokens(payload: payload, previousRefreshToken: "r1").refreshToken, "r1")
    }

    func testTokensWithoutAnyRefreshTokenAreRejected() {
        let payload = SpotifyTokens.Payload(access_token: "a2", refresh_token: nil, expires_in: 60)
        XCTAssertThrowsError(try SpotifyTokens(payload: payload, previousRefreshToken: nil))
    }

    func testTokensExpireAMinuteEarly() {
        let expiry = Date(timeIntervalSince1970: 10_000)
        let tokens = SpotifyTokens(accessToken: "a", refreshToken: "r", expiresAt: expiry)
        XCTAssertFalse(tokens.isExpired(at: expiry.addingTimeInterval(-61)))
        XCTAssertTrue(tokens.isExpired(at: expiry.addingTimeInterval(-60)))
        XCTAssertTrue(tokens.isExpired(at: expiry))
    }

    // MARK: Store

    func testStoreRoundTripsWithOwnerOnlyPermissions() throws {
        let store = temporaryStore()
        defer { store.clear() }
        XCTAssertNil(store.load())

        let tokens = SpotifyTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 5))
        try store.save(tokens)
        XCTAssertEqual(store.load(), tokens)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)

        store.clear()
        XCTAssertNil(store.load())
    }

    // MARK: Library requests

    func testLibraryURIOnlyAcceptsTracksAndEpisodes() {
        XCTAssertEqual(SpotifyProvider.libraryURI("spotify:track:4uLU6hMCjMI75M1A2tKUQC"), "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(SpotifyProvider.libraryURI("spotify:episode:abc"), "spotify:episode:abc")
        XCTAssertNil(SpotifyProvider.libraryURI("spotify:local:::Song:0"))
        XCTAssertNil(SpotifyProvider.libraryURI("spotify:ad:xyz"))
        XCTAssertNil(SpotifyProvider.libraryURI("spotify:track:"))
        XCTAssertNil(SpotifyProvider.libraryURI(""))
    }

    func testLibraryURLsUseTheCurrentEndpoints() throws {
        // `/v1/me/tracks` and `/v1/me/tracks/contains` are deprecated and answer 403 (measured 2026-09-04).
        let contains = try XCTUnwrap(URLComponents(url: SpotifyLibraryClient.containsURL(uri: "spotify:track:abc"), resolvingAgainstBaseURL: false))
        XCTAssertEqual(contains.host, "api.spotify.com")
        XCTAssertEqual(contains.path, "/v1/me/library/contains")
        XCTAssertEqual(contains.queryItems, [URLQueryItem(name: "uris", value: "spotify:track:abc")])

        let library = try XCTUnwrap(URLComponents(url: SpotifyLibraryClient.libraryURL(uri: "spotify:track:abc"), resolvingAgainstBaseURL: false))
        XCTAssertEqual(library.path, "/v1/me/library")
        XCTAssertEqual(library.queryItems, [URLQueryItem(name: "uris", value: "spotify:track:abc")])
    }

    // MARK: Loopback server

    func testLoopbackServerAnswersTheRedirectAndFreesThePort() async throws {
        let port: UInt16 = 48220
        let server = Task { try await SpotifyLoopbackServer.awaitCallback(port: port, timeout: .seconds(10)) }
        try await Task.sleep(for: .milliseconds(200))

        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/callback?code=abc&state=s1"))
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Spotify connected"))
        let callback = try await server.value
        XCTAssertEqual(callback, SpotifyPKCE.Callback(code: "abc", state: "s1", error: nil))

        // The listener is gone: the port can be taken again, and a lonely listener times out.
        do {
            _ = try await SpotifyLoopbackServer.awaitCallback(port: port, timeout: .milliseconds(300))
            XCTFail("expected a timeout")
        } catch let error as SpotifyLibraryError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testLoopbackServerStopsWhenTheConnectIsCancelled() async throws {
        let server = Task { try await SpotifyLoopbackServer.awaitCallback(port: 48221, timeout: .seconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        server.cancel()
        do {
            _ = try await server.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
    }

    // MARK: Connection state

    @MainActor
    func testClientStartsUnconfiguredUntilAClientIDIsSet() throws {
        let defaults = try isolatedDefaults()
        let store = temporaryStore()
        defer { store.clear() }

        let client = SpotifyLibraryClient(store: store, defaults: defaults)
        XCTAssertEqual(client.connection, .notConfigured)

        defaults.set("client-id", forKey: SpotifyLibraryClient.clientIDKey)
        client.refreshConfiguration()
        XCTAssertEqual(client.connection, .disconnected)
    }

    @MainActor
    func testClientStartsConnectedWithStoredTokensAndDisconnectClearsThem() throws {
        let defaults = try isolatedDefaults()
        let store = temporaryStore()
        defer { store.clear() }
        try store.save(SpotifyTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture))

        let client = SpotifyLibraryClient(store: store, defaults: defaults)
        XCTAssertEqual(client.connection, .connected)

        var changes = 0
        client.onChange = { changes += 1 }
        client.disconnect()
        XCTAssertEqual(client.connection, .notConfigured)
        XCTAssertNil(store.load())
        XCTAssertEqual(changes, 1)
    }

    // MARK: Helpers

    private func form(_ body: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
                .map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "" }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        })
    }

    private func temporaryStore() -> SpotifyTokenStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpotifyLibraryTests-\(UUID().uuidString)")
        return SpotifyTokenStore(fileURL: directory.appendingPathComponent("tokens.json"))
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "SpotifyLibraryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }
}
