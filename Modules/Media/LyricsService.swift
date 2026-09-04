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

    /// Per-song timing corrections the user made with the nudge controls, in seconds: positive
    /// shows the lyrics later. Keyed by `LyricsMatch.songKey` so a correction follows the song from
    /// one player to another, and kept in `UserDefaults` so it survives a relaunch.
    private(set) var shifts: [String: TimeInterval]

    /// Results per track. Definitive misses are cached too, so a track without lyrics is not looked
    /// up again; transient failures are not, so a flaky network does not hide lyrics for good.
    @ObservationIgnored private var cache: [String: LyricsStatus] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let defaults: UserDefaults

    static let shiftsKey = "lyricsShifts"
    /// One tap of the nudge control.
    static let shiftStep: TimeInterval = 0.5
    static let maxShift: TimeInterval = 15

    /// Off by default only if the user turned it off (`-lyricsEnabled NO`).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "lyricsEnabled") as? Bool ?? true
    }

    /// How far ahead of the audio the lyrics run, in seconds.
    ///
    /// A small lead reads better than a perfectly aligned one — the eye needs a moment to find the
    /// line. It is also the knob for output latency: Bluetooth headphones delay the sound by
    /// 150–300 ms, so a negative value pushes the lyrics back to match what is actually heard
    /// (`defaults write com.emre.mynotch lyricsLeadSeconds -0.1`).
    nonisolated static var lead: TimeInterval {
        UserDefaults.standard.object(forKey: "lyricsLeadSeconds") as? Double ?? 0.15
    }

    /// How long to wait before retrying after a network failure.
    static let retryDelay: Duration = .seconds(8)

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        shifts = defaults.dictionary(forKey: Self.shiftsKey) as? [String: TimeInterval] ?? [:]
    }

    // MARK: Timing corrections

    /// How much later than the file says this song's lyrics should show; negative is earlier.
    func shift(for state: MediaState) -> TimeInterval {
        shifts[LyricsMatch.songKey(artist: state.artist, title: state.title)] ?? 0
    }

    /// Moves this song's lyrics by `delta` seconds and remembers it.
    func nudge(_ state: MediaState, by delta: TimeInterval) {
        let key = LyricsMatch.songKey(artist: state.artist, title: state.title)
        let value = min(Self.maxShift, max(-Self.maxShift, (shifts[key] ?? 0) + delta))
        if abs(value) < 0.001 {
            shifts.removeValue(forKey: key)
        } else {
            shifts[key] = value
        }
        defaults.set(shifts, forKey: Self.shiftsKey)
    }

    func resetShift(for state: MediaState) {
        nudge(state, by: -shift(for: state))
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
            var outcome = await Self.fetch(for: state, session: session)
            if outcome == .failed {
                // One retry: a track that just started should not lose its lyrics to a hiccup.
                try? await Task.sleep(for: Self.retryDelay)
                guard !Task.isCancelled else { return }
                outcome = await Self.fetch(for: state, session: session)
            }
            guard !Task.isCancelled else { return }

            switch outcome {
            case .found(let lyrics):
                cache[key] = .loaded(lyrics)
                status = .loaded(lyrics)
            case .notFound:
                cache[key] = .unavailable
                status = .unavailable
            case .failed:
                status = .unavailable
            }
            if cache.count > 24 {
                cache.removeValue(forKey: cache.keys.first { $0 != key } ?? key)
            }
        }
    }

    func clear() {
        loadTask?.cancel()
        status = .idle
    }

    // MARK: Lookup chain

    nonisolated enum Outcome: Equatable {
        case found(Lyrics)
        /// Every step answered and none had lyrics.
        case notFound
        /// The network let us down; worth retrying.
        case failed
    }

    /// Several chances to find lyrics, cheapest first. Synced lyrics from any step win; the best
    /// plain-text record seen along the way is the fallback.
    ///
    /// 1. `/api/get` with everything we know — an exact hit, but its record often carries plain lyrics only;
    /// 2. `/api/search` with artist + title;
    /// 3. the same with the streaming suffix stripped ("… - Remastered", "… (Live)");
    /// 4. the primary artist only, for "A, B" and "A feat. B" credits;
    /// 5. a free-text query, which LRCLIB matches most loosely.
    private static func fetch(for state: MediaState, session: URLSession) async -> Outcome {
        var plainFallback: LRCLIBTrack?
        var sawFailure = false

        func consider(_ candidates: [LRCLIBTrack]) -> Lyrics? {
            if let best = bestCandidate(from: candidates, for: state),
               let lyrics = syncedLyrics(from: best, state: state) {
                return lyrics
            }
            if plainFallback == nil {
                plainFallback = bestPlainCandidate(from: candidates, for: state)
            }
            return nil
        }

        switch await request(getURL(for: state), session: session, decoding: LRCLIBTrack.self) {
        case .ok(let track):
            if let lyrics = consider([track]) { return .found(lyrics) }
        case .notFound: break
        case .failed: sawFailure = true
        }

        let simplified = simplifiedTitle(state.title)
        let primary = primaryArtist(state.artist)
        var searches: [URL?] = [searchURL(artist: state.artist, title: state.title)]
        if let simplified { searches.append(searchURL(artist: state.artist, title: simplified)) }
        if let primary { searches.append(searchURL(artist: primary, title: simplified ?? state.title)) }
        searches.append(freeTextSearchURL(artist: primary ?? state.artist, title: simplified ?? state.title))

        for url in searches {
            switch await request(url, session: session, decoding: [LRCLIBTrack].self) {
            case .ok(let results):
                if let lyrics = consider(results) { return .found(lyrics) }
            case .notFound: break
            case .failed: sawFailure = true
            }
        }

        if let plainFallback, let lyrics = plainLyrics(from: plainFallback, state: state) {
            return .found(lyrics)
        }
        return sawFailure ? .failed : .notFound
    }

    private enum Response<T> {
        case ok(T)
        case notFound
        case failed
    }

    private static func request<T: Decodable>(_ url: URL?, session: URLSession, decoding: T.Type) async -> Response<T> {
        guard let url else { return .notFound }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // LRCLIB asks clients to identify themselves.
        request.setValue("MyNotch/0.1.0 (https://github.com/Muhammethasanuyar/myNotch)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            // 404 means "nothing for this track", a normal answer rather than an error.
            if http.statusCode == 404 { return .notFound }
            guard http.statusCode == 200 else { return .failed }
            return .ok(try JSONDecoder().decode(T.self, from: data))
        } catch {
            return .failed
        }
    }

    private static func syncedLyrics(from track: LRCLIBTrack, state: MediaState) -> Lyrics? {
        guard track.instrumental != true, let synced = track.syncedLyrics, !synced.isEmpty else { return nil }
        let lines = LyricsParser.parse(synced)
        return lines.isEmpty ? nil : Lyrics(trackKey: state.artworkKey, lines: lines, isSynced: true)
    }

    /// Unsynced text spread evenly across the track: not the real timing, but close enough to
    /// read along with, and far better than an empty band.
    private static func plainLyrics(from track: LRCLIBTrack, state: MediaState) -> Lyrics? {
        guard track.instrumental != true, let plain = track.plainLyrics else { return nil }
        let lines = LyricsParser.spread(plain, over: state.duration ?? track.duration)
        return lines.isEmpty ? nil : Lyrics(trackKey: state.artworkKey, lines: lines, isSynced: false)
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

    /// `GET /api/search?q=…` — LRCLIB's loosest matching, the last resort.
    nonisolated static func freeTextSearchURL(artist: String, title: String) -> URL? {
        url(path: "/api/search", items: [URLQueryItem(name: "q", value: "\(artist) \(title)")])
    }

    private nonisolated static func url(path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://lrclib.net")
        components?.path = path
        components?.queryItems = items
        return components?.url
    }

    /// The search result worth using for synced lyrics: this song (title and artist agree), a cut
    /// of the same length, a file whose timings actually span the track. Ranking lives in
    /// `LyricsMatch`; a free-text search can return anything, so nothing here is taken on trust.
    nonisolated static func bestCandidate(from results: [LRCLIBTrack], for state: MediaState) -> LRCLIBTrack? {
        LyricsMatch.best(results, for: state, synced: true)
    }

    /// Same for records that only have unsynced text. Length matters little here — the text is
    /// spread over the track we are playing anyway — but it still has to be this song.
    nonisolated static func bestPlainCandidate(from results: [LRCLIBTrack], for state: MediaState) -> LRCLIBTrack? {
        LyricsMatch.best(results, for: state, synced: false)
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

    /// The first credited artist of "A, B", "A & B", "A feat. B" or "A x B". `nil` when the credit
    /// is already a single name.
    nonisolated static func primaryArtist(_ artist: String) -> String? {
        let separators = [", ", " & ", " feat. ", " Feat. ", " ft. ", " Ft. ", " x ", " X "]
        var result = Substring(artist)
        for separator in separators {
            if let range = result.range(of: separator) { result = result[..<range.lowerBound] }
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == artist ? nil : trimmed
    }
}

/// The subset of LRCLIB's track payload we use. The names are what lets `LyricsMatch` tell this
/// song from the others a loose search drags in.
nonisolated struct LRCLIBTrack: Decodable, Equatable {
    let duration: Double?
    let instrumental: Bool?
    let syncedLyrics: String?
    let plainLyrics: String?
    let trackName: String?
    let artistName: String?
    let albumName: String?

    init(duration: Double? = nil, instrumental: Bool? = false, syncedLyrics: String? = nil, plainLyrics: String? = nil,
         trackName: String? = nil, artistName: String? = nil, albumName: String? = nil) {
        self.duration = duration
        self.instrumental = instrumental
        self.syncedLyrics = syncedLyrics
        self.plainLyrics = plainLyrics
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
    }
}
