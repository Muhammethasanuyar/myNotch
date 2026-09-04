import Foundation

/// Decides whether an LRCLIB record is *this* song and how well its timings fit the recording that
/// is playing.
///
/// The lookup chain widens on purpose — its last step is a free-text search — so results can hold
/// other songs, other cuts of the same song and half-finished uploads. Choosing by "closest
/// duration" alone trusts all of them equally; this ranks identity first and fit second, and
/// refuses timings that cannot belong to the recording in the player.
nonisolated enum LyricsMatch {
    /// Synced timings are only trusted from a cut of (nearly) the same length.
    static let syncedDurationTolerance: TimeInterval = 8
    /// A synced file whose last line lies this far past the end of the track was made for another cut.
    static let overrunTolerance: TimeInterval = 3
    /// Words in a title qualifier that mean "a different recording", not a different label for the same one.
    static let versionWords = ["live", "remix", "acoustic", "akustik", "instrumental", "karaoke", "demo", "cover", "version", "versiyon", "edit", "mix", "unplugged", "konser"]

    // MARK: Text

    /// Lowercase, accents folded (ı, ş, ğ, ç, ö, ü, İ all become plain letters), punctuation gone,
    /// single spaces — so "Tatlısert" and "Tatlı Sert" can meet.
    static func normalize(_ text: String) -> String {
        let folded = text
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")   // dotless ı has no decomposition to fold
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = String(String.UnicodeScalarView(folded.unicodeScalars.map { allowed.contains($0) ? $0 : " " }))
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `normalize` without spaces, for equality tests that should not care where words break.
    static func compact(_ text: String) -> String {
        normalize(text).replacingOccurrences(of: " ", with: "")
    }

    /// The title proper and the qualifiers streaming services and scrobblers hang off it:
    /// "Song - Remastered 2011" → ("song", ["remastered 2011"]), "Song (Paused)" → ("song", ["paused"]).
    static func baseTitle(_ title: String) -> (base: String, qualifiers: [String]) {
        var qualifiers: [String] = []
        var working = title
        // Parenthesised or bracketed groups anywhere.
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = working.range(of: open), let end = working[start.upperBound...].range(of: close) {
                qualifiers.append(normalize(String(working[start.upperBound..<end.lowerBound])))
                working.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        // A " - " suffix: "Song - Live at Wembley".
        if let dash = working.range(of: " - ") {
            qualifiers.append(normalize(String(working[dash.upperBound...])))
            working = String(working[..<dash.lowerBound])
        }
        return (normalize(working), qualifiers.filter { !$0.isEmpty })
    }

    /// Artist names as the catalogues write them, minus the noise YouTube-derived uploads carry.
    static func normalizedArtist(_ artist: String) -> String {
        var name = normalize(artist)
        for noise in [" topic", " vevo", " official"] where name.hasSuffix(noise) {
            name = String(name.dropLast(noise.count))
        }
        return name
    }

    /// The names in a credit — "A, B", "A & B", "A feat. B", "A x B" — each normalized. Split on
    /// the raw text: normalizing first would turn the commas and ampersands into spaces.
    static func creditedArtists(_ artist: String) -> [String] {
        var parts = [artist]
        for separator in [",", "&", " feat. ", " feat ", " Feat. ", " ft. ", " ft ", " Ft. ", " x ", " X ", " with "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map(normalizedArtist).filter { !$0.isEmpty }
    }

    static func artistMatches(candidate: String, requested: String) -> Bool {
        let c = compact(normalizedArtist(candidate))
        let r = compact(normalizedArtist(requested))
        if c == r { return true }
        if c.count >= 3, r.count >= 3, c.contains(r) || r.contains(c) { return true }
        let credited = creditedArtists(requested).map(compact)
        return credited.contains { $0.count >= 3 && c.contains($0) }
    }

    enum TitleMatch: Equatable, Sendable {
        case exact
        /// One title is the other plus `extra` words at a word boundary ("Song" / "Song 2015 Version").
        /// Plain substrings are not enough: "Sen" must not match "Sensiz".
        case contained(extra: String)
        case none
    }

    static func titleMatch(candidate: String, requested: String) -> TitleMatch {
        let c = baseTitle(candidate).base
        let r = baseTitle(requested).base
        guard !c.isEmpty, !r.isEmpty else { return .none }
        if compact(c) == compact(r) { return .exact }
        let (short, long) = c.count < r.count ? (c, r) : (r, c)
        guard short.count >= 6 else { return .none }
        if long.hasPrefix(short + " ") { return .contained(extra: String(long.dropFirst(short.count + 1))) }
        if long.hasSuffix(" " + short) { return .contained(extra: String(long.dropLast(short.count + 1))) }
        return .none
    }

    /// Whether any word names a different recording.
    static func namesAnotherVersion(_ words: String) -> Bool {
        words.split(separator: " ").contains { versionWords.contains(String($0)) }
    }

    /// Qualifiers on one side but not the other that name a different recording.
    static func hasVersionMismatch(candidate: String, requested: String) -> Bool {
        let c = Set(baseTitle(candidate).qualifiers)
        let r = Set(baseTitle(requested).qualifiers)
        return c.symmetricDifference(r).contains(where: namesAnotherVersion)
    }

    // MARK: Scoring

    /// How well `track` fits, higher is better; `nil` when it is not this song or its timings
    /// cannot belong to the recording being played.
    static func score(_ track: LRCLIBTrack, for state: MediaState, synced: Bool) -> Int? {
        guard track.instrumental != true else { return nil }
        let lyrics = synced ? track.syncedLyrics : track.plainLyrics
        guard let lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var score = 0

        // Identity. Records without names cannot be checked and are taken at their word.
        if let name = track.trackName {
            var otherVersion = hasVersionMismatch(candidate: name, requested: state.title)
            switch titleMatch(candidate: name, requested: state.title) {
            case .exact:
                score += 30
            case .contained(let extra):
                score += 10
                if namesAnotherVersion(extra) { otherVersion = true }
            case .none:
                return nil
            }
            if otherVersion {
                if synced { return nil }   // a live or remixed cut cannot share timings with this one
                score -= 15
            }
            let stray = Set(baseTitle(name).qualifiers).subtracting(baseTitle(state.title).qualifiers)
            score -= 5 * stray.count   // "(Paused)" and friends
        }
        if let artist = track.artistName {
            guard artistMatches(candidate: artist, requested: state.artist) else { return nil }
            score += compact(normalizedArtist(artist)) == compact(normalizedArtist(state.artist)) ? 15 : 5
        }
        if let album = track.albumName, !state.album.isEmpty, !album.localizedCaseInsensitiveContains("unknown") {
            let c = compact(album), r = compact(state.album)
            if c == r { score += 12 } else if c.contains(r) || r.contains(c) { score += 6 }
        }

        // Fit with the recording.
        if let mine = state.duration, mine > 0 {
            if let theirs = track.duration {
                let delta = abs(theirs - mine)
                if synced, delta > syncedDurationTolerance { return nil }
                score -= Int(min(delta, 30) * 2)
            } else {
                score -= 5
            }
            if synced {
                let lines = LyricsParser.parse(lyrics).filter { !$0.text.isEmpty }
                guard let last = lines.last?.time else { return nil }
                if last > mine + overrunTolerance { return nil }   // written for a longer cut
                if last < mine * 0.4 { score -= 20 }                // the upload stops half way
                score += min(lines.count, 60) / 6
            }
        }
        return score
    }

    /// The record worth using, or `nil` when none is this song with usable lyrics.
    static func best(_ tracks: [LRCLIBTrack], for state: MediaState, synced: Bool) -> LRCLIBTrack? {
        tracks
            .compactMap { track in score(track, for: state, synced: synced).map { (track, $0) } }
            .max { $0.1 < $1.1 }?.0
    }

    /// Identity of a song across players, for remembering per-song corrections.
    static func songKey(artist: String, title: String) -> String {
        "\(compact(normalizedArtist(artist)))|\(compact(baseTitle(title).base))"
    }
}
