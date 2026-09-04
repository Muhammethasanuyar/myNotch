import CryptoKit
import Foundation

/// PKCE plumbing for Spotify's authorization-code flow (RFC 7636). Pure, so every piece is tested
/// without a network or a browser.
///
/// The flow: open `authorizationURL` in the browser, catch the redirect on the loopback server,
/// then trade the `code` for tokens with `tokenExchangeRequest`. No client secret is involved.
nonisolated enum SpotifyPKCE {
    static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    /// Read the library to show the heart's state; modify it to toggle it.
    static let scopes = ["user-library-read", "user-library-modify"]
    /// Fixed, so the redirect URI registered once in the Spotify dashboard never has to change.
    static let callbackPort: UInt16 = 48219
    static var redirectURI: String { "http://127.0.0.1:\(callbackPort)/callback" }

    /// 64 characters from RFC 7636's unreserved set.
    static func makeVerifier() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in alphabet.randomElement()! })
    }

    /// `BASE64URL(SHA256(verifier))`.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func authorizationURL(clientID: String, verifier: String, state: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    static func tokenExchangeRequest(code: String, verifier: String, clientID: String) -> URLRequest {
        formRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
    }

    static func refreshRequest(refreshToken: String, clientID: String) -> URLRequest {
        formRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
    }

    /// Result of the browser's redirect back to us.
    struct Callback: Equatable, Sendable {
        let code: String?
        let state: String?
        let error: String?
    }

    /// Parses the first line of the HTTP request the browser makes to the loopback server, e.g.
    /// `GET /callback?code=AQ…&state=xyz HTTP/1.1`. `nil` for anything that is not our callback.
    static func callback(fromRequestLine line: String) -> Callback? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
              components.path == "/callback" else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        return Callback(code: value("code"), state: value("state"), error: value("error"))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formRequest(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = fields.sorted { $0.key < $1.key }
            .map { "\(formEncoded($0.key))=\(formEncoded($0.value))" }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)
        return request
    }

    /// `application/x-www-form-urlencoded` escaping: everything outside the unreserved set,
    /// including `+`, `/` and `:` which `URLComponents` would leave alone in a query.
    static func formEncoded(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

/// What Spotify hands back and what we keep.
nonisolated struct SpotifyTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// Treat the token as stale a minute early so a request never races the expiry.
    func isExpired(at now: Date = Date()) -> Bool {
        now >= expiresAt.addingTimeInterval(-60)
    }

    /// Spotify's token payload. A refresh may or may not rotate the refresh token.
    struct Payload: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }

    init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    init(payload: Payload, previousRefreshToken: String?, now: Date = Date()) throws {
        guard let refresh = payload.refresh_token ?? previousRefreshToken else {
            throw SpotifyLibraryError.malformedResponse("token payload without a refresh token")
        }
        self.init(accessToken: payload.access_token, refreshToken: refresh, expiresAt: now.addingTimeInterval(payload.expires_in))
    }
}

nonisolated enum SpotifyLibraryError: Error, Equatable {
    case notConfigured
    case notConnected
    case authorizationDenied(String)
    case stateMismatch
    case timedOut
    case httpStatus(Int)
    case malformedResponse(String)
    /// Local files and ads have no library entry.
    case notSaveable(String)
}
