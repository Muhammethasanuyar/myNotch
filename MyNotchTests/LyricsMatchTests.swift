import XCTest
@testable import MyNotch

final class LyricsMatchTests: XCTestCase {
    private func state(title: String = "Bu Sabahların Bir Anlamı Olmalı", artist: String = "Vega", album: String = "Tatlısert", duration: TimeInterval? = 269.4) -> MediaState {
        MediaState(providerID: "spotify", providerName: "Spotify", trackID: "t", title: title, artist: artist, album: album,
                   isPlaying: true, duration: duration, elapsed: 0, elapsedAt: Date(), artwork: nil)
    }

    /// An LRC body with `count` lines spread up to `last` seconds.
    private func lrc(lines count: Int, last: TimeInterval) -> String {
        (0..<count).map { index in
            let time = 34 + (last - 34) * Double(index) / Double(max(1, count - 1))
            return String(format: "[%02d:%05.2f] satır %d", Int(time) / 60, time - Double(Int(time) / 60 * 60), index)
        }.joined(separator: "\n")
    }

    private func record(title: String = "Bu Sabahların Bir Anlamı Olmalı", artist: String = "Vega", album: String = "Tatlı Sert",
                        duration: Double, lines: Int = 53, last: TimeInterval = 243, plainOnly: Bool = false) -> LRCLIBTrack {
        LRCLIBTrack(
            duration: duration,
            instrumental: false,
            syncedLyrics: plainOnly ? nil : lrc(lines: lines, last: last),
            plainLyrics: "sözler\nsözler",
            trackName: title,
            artistName: artist,
            albumName: album
        )
    }

    // MARK: Text

    func testNormalizationFoldsTurkishLettersAndPunctuation() {
        XCTAssertEqual(LyricsMatch.normalize("Bu Sabahların Bir Anlamı Olmalı"), "bu sabahlarin bir anlami olmali")
        XCTAssertEqual(LyricsMatch.normalize("İSTANBUL'da, Şöyle-Böyle!"), "istanbul da soyle boyle")
        XCTAssertEqual(LyricsMatch.compact("Tatlısert"), LyricsMatch.compact("Tatlı Sert"), "the album as Spotify spells it and as LRCLIB does")
    }

    func testTitlesLoseTheirQualifiers() {
        XCTAssertEqual(LyricsMatch.baseTitle("Song - Remastered 2011").base, "song")
        XCTAssertEqual(LyricsMatch.baseTitle("Song - Remastered 2011").qualifiers, ["remastered 2011"])
        XCTAssertEqual(LyricsMatch.baseTitle("Bu Sabahların Bir Anlamı Olmalı (Paused)").qualifiers, ["paused"])
        XCTAssertEqual(LyricsMatch.baseTitle("Song [Live] (Acoustic)").qualifiers.sorted(), ["acoustic", "live"])
    }

    func testTitleMatchingNeedsWholeWords() {
        XCTAssertEqual(LyricsMatch.titleMatch(candidate: "Bu Sabahların Bir Anlamı Olmalı (Paused)", requested: "Bu Sabahların Bir Anlamı Olmalı"), .exact)
        XCTAssertEqual(LyricsMatch.titleMatch(candidate: "Duman 2015 Version", requested: "Duman"), .none, "six letters at least before a longer title may match")
        XCTAssertEqual(LyricsMatch.titleMatch(candidate: "Okyanus 2015 Version", requested: "Okyanus"), .contained(extra: "2015 version"))
        XCTAssertTrue(LyricsMatch.namesAnotherVersion("2015 version"), "and those extra words mark another cut")
        XCTAssertEqual(LyricsMatch.titleMatch(candidate: "Bir Sevmek Bin Defa Ölmek Demekmiş", requested: "Bir Sevmek Bin Defa Ölmek Demekmiş Feridun Hürel Albüm"), .contained(extra: "feridun hurel album"))
        XCTAssertEqual(LyricsMatch.titleMatch(candidate: "Sensiz", requested: "Sen"), .none, "Sen is not Sensiz")
        XCTAssertEqual(LyricsMatch.titleMatch(candidate: "Bu Akşam", requested: "Bu Sabahların Bir Anlamı Olmalı"), .none)
    }

    func testArtistMatchingForgivesCatalogueNoiseAndCoCredits() {
        XCTAssertTrue(LyricsMatch.artistMatches(candidate: "Vega - Topic", requested: "Vega"))
        XCTAssertTrue(LyricsMatch.artistMatches(candidate: "Fatma Turgut", requested: "Fatma Turgut, Sagopa Kajmer"))
        XCTAssertTrue(LyricsMatch.artistMatches(candidate: "Mabel Matiz feat. Sezen Aksu", requested: "Mabel Matiz"))
        XCTAssertFalse(LyricsMatch.artistMatches(candidate: "Duman", requested: "Vega"))
        XCTAssertEqual(LyricsMatch.creditedArtists("Ezhel & Ufo361"), ["ezhel", "ufo361"])
    }

    func testVersionWordsMarkAnotherRecording() {
        XCTAssertTrue(LyricsMatch.hasVersionMismatch(candidate: "Song (Live)", requested: "Song"))
        XCTAssertTrue(LyricsMatch.hasVersionMismatch(candidate: "Song", requested: "Song - Akustik"))
        XCTAssertFalse(LyricsMatch.hasVersionMismatch(candidate: "Song (Live)", requested: "Song (Live)"))
        XCTAssertFalse(LyricsMatch.hasVersionMismatch(candidate: "Song (Paused)", requested: "Song"), "a scrobbler artefact is not a different cut")
    }

    // MARK: Ranking, on the records LRCLIB really returned for the Vega track on 2026-09-05

    func testTheSameCutWithTheMatchingAlbumWinsOverItsCopies() throws {
        let results = [
            record(album: "Unknown Album", duration: 288, lines: 22, last: 143),          // half finished, wrong length
            record(album: "Tatlı Sert", duration: 269),                                   // the one to pick
            record(album: "Unknown Album", duration: 268),
            record(album: "Tatlı Sert 2", duration: 268, lines: 41, last: 245),
            record(album: "Tatlı Sert", duration: 289),
            record(album: "Tatlı Sert", duration: 230),                                   // lines run past its own length
            record(album: "Tatlı Sert", duration: 255),
            record(artist: "Vega - Topic", album: "BU SABAH Bİ UMUT VAR İÇİMDE", duration: 269),
            record(title: "Bu Sabahların Bir Anlamı Olmalı (Paused)", duration: 269)
        ]
        let best = try XCTUnwrap(LyricsMatch.best(results, for: state(), synced: true))
        XCTAssertEqual(best.albumName, "Tatlı Sert")
        XCTAssertEqual(best.duration, 269)
        XCTAssertEqual(best.artistName, "Vega")
        XCTAssertEqual(best.trackName, "Bu Sabahların Bir Anlamı Olmalı")
    }

    func testAnotherSongIsNeverPickedHoweverWellItsLengthFits() {
        let results = [
            record(title: "Bu Akşam", artist: "Duman", album: "Belki Alışman Lazım", duration: 269),
            record(duration: 272, plainOnly: true)
        ]
        XCTAssertNil(LyricsMatch.best(results, for: state(), synced: true), "the only synced record is a different song")
        XCTAssertEqual(LyricsMatch.best(results, for: state(), synced: false)?.duration, 272, "so the right song's plain text is the answer")
    }

    func testAnotherCutOfTheSameSongIsRefusedForTimings() {
        let live = record(title: "Bu Sabahların Bir Anlamı Olmalı (Live)", duration: 269)
        XCTAssertNil(LyricsMatch.best([live], for: state(), synced: true))
        XCTAssertNotNil(LyricsMatch.best([live], for: state(), synced: false), "its words are still this song's")
        XCTAssertNil(LyricsMatch.best([record(duration: 269 + 12)], for: state(), synced: true), "twelve seconds longer is another master")
        XCTAssertNil(LyricsMatch.best([record(duration: 269, last: 280)], for: state(), synced: true), "lines past the end of the track were timed for something else")
    }

    func testACompleteFileBeatsAnAbandonedOne() throws {
        let abandoned = record(album: "Unknown Album", duration: 269, lines: 5, last: 60)
        let complete = record(album: "Unknown Album", duration: 268, lines: 41, last: 245)
        XCTAssertEqual(try XCTUnwrap(LyricsMatch.best([abandoned, complete], for: state(), synced: true)).duration, 268)
        XCTAssertEqual(LyricsMatch.best([abandoned], for: state(), synced: true)?.duration, 269, "alone, a partial file still beats nothing")
    }

    func testRecordsWithoutNamesAreTakenAtTheirWord() {
        let nameless = LRCLIBTrack(duration: 269, instrumental: false, syncedLyrics: lrc(lines: 30, last: 240))
        XCTAssertNotNil(LyricsMatch.best([nameless], for: state(), synced: true))
    }

    func testSongKeyFollowsTheSongAcrossPlayers() {
        XCTAssertEqual(
            LyricsMatch.songKey(artist: "Vega", title: "Bu Sabahların Bir Anlamı Olmalı"),
            LyricsMatch.songKey(artist: "Vega - Topic", title: "Bu Sabahların Bir Anlamı Olmalı (Paused)")
        )
        XCTAssertNotEqual(LyricsMatch.songKey(artist: "Vega", title: "Sen"), LyricsMatch.songKey(artist: "Vega", title: "Sensiz"))
    }
}

@MainActor
final class LyricsShiftTests: XCTestCase {
    private func makeService() throws -> (LyricsService, UserDefaults) {
        let suite = "LyricsShiftTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (LyricsService(defaults: defaults), defaults)
    }

    private let state = MediaState(providerID: "spotify", providerName: "Spotify", trackID: "t", title: "Bu Sabahların Bir Anlamı Olmalı",
                                   artist: "Vega", album: "Tatlısert", isPlaying: true, duration: 269, elapsed: 0, elapsedAt: Date(), artwork: nil)

    func testNudgesAccumulateAndPersist() throws {
        let (service, defaults) = try makeService()
        XCTAssertEqual(service.shift(for: state), 0)
        service.nudge(state, by: 0.5)
        service.nudge(state, by: 0.5)
        XCTAssertEqual(service.shift(for: state), 1.0)

        let again = LyricsService(defaults: defaults)
        XCTAssertEqual(again.shift(for: state), 1.0, "a correction survives a relaunch")
    }

    func testResetForgetsTheSong() throws {
        let (service, defaults) = try makeService()
        service.nudge(state, by: -1.5)
        service.resetShift(for: state)
        XCTAssertEqual(service.shift(for: state), 0)
        XCTAssertNil((defaults.dictionary(forKey: LyricsService.shiftsKey) ?? [:])[LyricsMatch.songKey(artist: "Vega", title: "Bu Sabahların Bir Anlamı Olmalı")])
    }

    func testShiftIsClamped() throws {
        let (service, _) = try makeService()
        for _ in 0..<100 { service.nudge(state, by: 0.5) }
        XCTAssertEqual(service.shift(for: state), LyricsService.maxShift)
    }

    func testShiftLabel() {
        XCTAssertEqual(MediaLyricsView.shiftLabel(0.5), "+0.5 s")
        XCTAssertEqual(MediaLyricsView.shiftLabel(-1), "−1.0 s")
    }
}
