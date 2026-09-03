import Foundation
import Observation

/// Fetches timed lyrics for the current track from LRCLIB (https://lrclib.net) — a free, key-less
/// community database that returns LRC-formatted synced lyrics.
///
/// Privacy: this sends the artist, title, album and duration of what you are playing to lrclib.net.
/// Nothing else leaves the machine, and the whole feature can be switched off (`lyricsEnabled`,
/// surfaced in Settings in Phase 5).
@MainActor
@Observable
final class LyricsService {
    private(set) var status: LyricsStatus = .idle

    /// Results per track, including negative ones so a missing track is not looked up twice.
    @ObservationIgnored private var cache: [String: LyricsStatus] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession

    /// Off by default only if the user turned it off (`-lyricsEnabled NO`).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "lyricsEnabled") as? Bool ?? true
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Loads lyrics for `state`, reusing anything already looked up for that track.
    func load(for state: MediaState?) {
        loadTask?.cancel()
        guard isEnabled, let state, state.hasContent else {
            status = .idle
            return
        }
        let key = state.artworkKey
        if let cached = cache[key] {
            status = cached
            return
        }

        status = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await Self.fetch(for: state, session: session)
            guard !Task.isCancelled else { return }
            cache[key] = result
            if cache.count > 24 {
                cache.removeValue(forKey: cache.keys.first { $0 != key } ?? key)
            }
            status = result
        }
    }

    func clear() {
        loadTask?.cancel()
        status = .idle
    }

    // MARK: Networking

    /// Three chances to find timed lyrics, cheapest first:
    /// 1. `/api/get` with everything we know — an exact hit, but its record may only carry plain lyrics;
    /// 2. `/api/search` with artist + title — several records, one of which usually has the synced set;
    /// 3. the same search with a simplified title, for "… - Remastered" style suffixes.
    private static func fetch(for state: MediaState, session: URLSession) async -> LyricsStatus {
        if let track = await request(getURL(for: state), session: session, decoding: LRCLIBTrack.self),
           let status = status(from: track, state: state) {
            return status
        }
        if let results = await request(searchURL(artist: state.artist, title: state.title), session: session, decoding: [LRCLIBTrack].self),
           let best = bestCandidate(from: results, duration: state.duration),
           let status = status(from: best, state: state) {
            return status
        }
        if let simplified = simplifiedTitle(state.title),
           let results = await request(searchURL(artist: state.artist, title: simplified), session: session, decoding: [LRCLIBTrack].self),
           let best = bestCandidate(from: results, duration: state.duration),
           let status = status(from: best, state: state) {
            return status
        }
        return .unavailable
    }

    private static func request<T: Decodable>(_ url: URL?, session: URLSession, decoding: T.Type) async -> T? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // LRCLIB asks clients to identify themselves.
        request.setValue("MyNotch/0.1.0 (https://github.com/Muhammethasanuyar/myNotch)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            // 404 means "nothing for this track", which is a normal answer rather than an error.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private static func status(from track: LRCLIBTrack, state: MediaState) -> LyricsStatus? {
        guard track.instrumental != true, let synced = track.syncedLyrics, !synced.isEmpty else { return nil }
        let lines = LyricsParser.parse(synced)
        return lines.isEmpty ? nil : .loaded(Lyrics(trackKey: state.artworkKey, lines: lines))
    }

    // MARK: Request building and candidate selection (pure)

    /// `GET /api/get?artist_name=…&track_name=…&album_name=…&duration=…`
    nonisolated static func getURL(for state: MediaState) -> URL? {
        var items = [
            URLQueryItem(name: "artist_name", value: state.artist),
            URLQueryItem(name: "track_name", value: state.title)
        ]
        if !state.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: state.album))
        }
        if let duration = state.duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        return url(path: "/api/get", items: items)
    }

    /// `GET /api/search?artist_name=…&track_name=…`
    nonisolated static func searchURL(artist: String, title: String) -> URL? {
        url(path: "/api/search", items: [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ])
    }

    private nonisolated static func url(path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://lrclib.net")
        components?.path = path
        components?.queryItems = items
        return components?.url
    }

    /// Picks the search result worth using: it must actually carry synced lyrics, and among those
    /// the one whose length is closest to what the player reports wins.
    nonisolated static func bestCandidate(from results: [LRCLIBTrack], duration: TimeInterval?) -> LRCLIBTrack? {
        let usable = results.filter { $0.instrumental != true && !($0.syncedLyrics ?? "").isEmpty }
        guard let duration else { return usable.first }
        return usable.min { lhs, rhs in
            abs((lhs.duration ?? .greatestFiniteMagnitude) - duration) < abs((rhs.duration ?? .greatestFiniteMagnitude) - duration)
        }
    }

    /// Strips the decorations streaming services add — "Song - Remastered 2011", "Song (Live)" —
    /// so a second search has a chance. `nil` when there is nothing to strip.
    nonisolated static func simplifiedTitle(_ title: String) -> String? {
        var trimmed = Substring(title)
        if let range = trimmed.range(of: " - ") { trimmed = trimmed[..<range.lowerBound] }
        if let range = trimmed.range(of: " (") { trimmed = trimmed[..<range.lowerBound] }
        let result = trimmed.trimmingCharacters(in: .whitespaces)
        return result.isEmpty || result == title ? nil : result
    }
}

/// The subset of LRCLIB's track payload we use.
nonisolated struct LRCLIBTrack: Decodable, Equatable {
    let duration: Double?
    let instrumental: Bool?
    let syncedLyrics: String?

    init(duration: Double? = nil, instrumental: Bool? = false, syncedLyrics: String? = nil) {
        self.duration = duration
        self.instrumental = instrumental
        self.syncedLyrics = syncedLyrics
    }
}
