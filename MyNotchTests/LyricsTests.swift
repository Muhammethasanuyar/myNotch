import XCTest
@testable import MyNotch

final class LyricsParserTests: XCTestCase {
    func testParsesTimestampedLines() {
        let lrc = """
        [00:13.28] Eh-eh, eh-eh
        [00:18.13] Otro sunset bonito que veo en San Juan
        [01:05.00]Sin espacio tras el corchete
        """
        let lines = LyricsParser.parse(lrc)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].time, 13.28, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "Eh-eh, eh-eh")
        XCTAssertEqual(lines[1].time, 18.13, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 65, accuracy: 0.001)
        XCTAssertEqual(lines[2].text, "Sin espacio tras el corchete")
    }

    func testAcceptsSecondsWithoutFractionAndWithMilliseconds() {
        let lines = LyricsParser.parse("[00:05]Beş\n[00:07.500]Yedi buçuk")
        XCTAssertEqual(lines[0].time, 5, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 7.5, accuracy: 0.001)
    }

    func testExpandsSeveralTimestampsSharingOneLine() {
        let lines = LyricsParser.parse("[00:10.00][01:10.00][02:10.00]Nakarat")
        XCTAssertEqual(lines.map(\.time), [10, 70, 130])
        XCTAssertTrue(lines.allSatisfy { $0.text == "Nakarat" })
    }

    func testIgnoresMetadataTags() {
        let lrc = """
        [ar:Bad Bunny]
        [ti:DtMF]
        [al:DeBÍ TiRAR MáS FOToS]
        [by:someone]
        [00:01.00]İlk satır
        """
        let lines = LyricsParser.parse(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "İlk satır")
    }

    func testAppliesTheOffsetTag() {
        let lines = LyricsParser.parse("[offset:+500]\n[00:10.00]Geç\n[00:00.10]Sıfıra kırpılır")
        XCTAssertEqual(lines.last?.time ?? 0, 10.5, accuracy: 0.001)
        XCTAssertEqual(lines.first?.time ?? -1, 0.6, accuracy: 0.001)
    }

    func testKeepsEmptyLinesSoIntrosGoBlank() {
        let lines = LyricsParser.parse("[00:00.00]\n[00:12.00]Söz başlıyor")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "")
    }

    func testSortsOutOfOrderInput() {
        let lines = LyricsParser.parse("[00:30.00]Sonra\n[00:10.00]Önce")
        XCTAssertEqual(lines.map(\.text), ["Önce", "Sonra"])
    }

    func testIgnoresGarbage() {
        XCTAssertTrue(LyricsParser.parse("").isEmpty)
        XCTAssertTrue(LyricsParser.parse("düz metin, zaman damgası yok").isEmpty)
        XCTAssertTrue(LyricsParser.parse("[not a timestamp]metin").isEmpty)
    }

    // MARK: Current line lookup

    private let lines = [
        LyricsLine(time: 10, text: "bir"),
        LyricsLine(time: 20, text: "iki"),
        LyricsLine(time: 30, text: "üç")
    ]

    func testNothingIsActiveBeforeTheFirstTimestamp() {
        XCTAssertNil(LyricsParser.index(at: 0, in: lines))
        XCTAssertNil(LyricsParser.index(at: 9.99, in: lines))
        XCTAssertNil(LyricsParser.index(at: 5, in: []))
    }

    func testTheLineHoldsUntilTheNextOneStarts() {
        XCTAssertEqual(LyricsParser.index(at: 10, in: lines), 0)
        XCTAssertEqual(LyricsParser.index(at: 19.9, in: lines), 0)
        XCTAssertEqual(LyricsParser.index(at: 20, in: lines), 1)
        XCTAssertEqual(LyricsParser.index(at: 29.5, in: lines), 1)
    }

    func testTheLastLineStaysActiveToTheEnd() {
        XCTAssertEqual(LyricsParser.index(at: 30, in: lines), 2)
        XCTAssertEqual(LyricsParser.index(at: 600, in: lines), 2)
    }
}

final class LyricsServiceTests: XCTestCase {
    private func state(title: String, artist: String, album: String = "Album", duration: TimeInterval? = 237) -> MediaState {
        MediaState(
            providerID: "spotify",
            providerName: "Spotify",
            trackID: "t",
            title: title,
            artist: artist,
            album: album,
            isPlaying: true,
            duration: duration,
            elapsed: 0,
            elapsedAt: Date(),
            artwork: nil
        )
    }

    func testGetURLCarriesEveryLookupField() throws {
        let url = try XCTUnwrap(LyricsService.getURL(for: state(title: "DtMF", artist: "Bad Bunny")))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.host, "lrclib.net")
        XCTAssertEqual(components.path, "/api/get")
        XCTAssertEqual(items["artist_name"], "Bad Bunny")
        XCTAssertEqual(items["track_name"], "DtMF")
        XCTAssertEqual(items["album_name"], "Album")
        XCTAssertEqual(items["duration"], "237", "the duration is rounded to whole seconds")
    }

    func testGetURLSkipsUnknownFieldsAndEscapesTheRest() throws {
        let url = try XCTUnwrap(LyricsService.getURL(for: state(title: "Ne İş?", artist: "Sanatçı & Co", album: "", duration: nil)))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertNil(items.first { $0.name == "album_name" })
        XCTAssertNil(items.first { $0.name == "duration" })
        XCTAssertEqual(items.first { $0.name == "track_name" }?.value, "Ne İş?")
        XCTAssertTrue(url.absoluteString.contains("Sanat%C3%A7%C4%B1%20%26%20Co"))
    }

    func testSearchURLCarriesArtistAndTitleOnly() throws {
        let url = try XCTUnwrap(LyricsService.searchURL(artist: "Madrigal", title: "Bir Sevmek"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/search")
        XCTAssertEqual(components.queryItems?.count, 2)
    }

    func testCandidateMustActuallyHaveSyncedLyrics() {
        // The real case this exists for: /api/get matched a record that only had plain lyrics.
        let results = [
            LRCLIBTrack(duration: 248, instrumental: false, syncedLyrics: nil),
            LRCLIBTrack(duration: 248.2, instrumental: false, syncedLyrics: "[00:10.00]satır")
        ]
        XCTAssertEqual(LyricsService.bestCandidate(from: results, duration: 248)?.syncedLyrics, "[00:10.00]satır")
    }

    func testCandidateClosestInLengthWins() {
        let results = [
            LRCLIBTrack(duration: 180, instrumental: false, syncedLyrics: "[00:01.00]kısa"),
            LRCLIBTrack(duration: 246, instrumental: false, syncedLyrics: "[00:01.00]doğru"),
            LRCLIBTrack(duration: 400, instrumental: false, syncedLyrics: "[00:01.00]uzun")
        ]
        XCTAssertEqual(LyricsService.bestCandidate(from: results, duration: 248)?.syncedLyrics, "[00:01.00]doğru")
    }

    func testInstrumentalsAndEmptyResultsAreRejected() {
        XCTAssertNil(LyricsService.bestCandidate(from: [], duration: 200))
        let instrumental = [LRCLIBTrack(duration: 200, instrumental: true, syncedLyrics: "[00:01.00]x")]
        XCTAssertNil(LyricsService.bestCandidate(from: instrumental, duration: 200))
    }

    func testTitleSimplificationStripsStreamingSuffixes() {
        XCTAssertEqual(LyricsService.simplifiedTitle("Song - Remastered 2011"), "Song")
        XCTAssertEqual(LyricsService.simplifiedTitle("Song (Live)"), "Song")
        XCTAssertEqual(LyricsService.simplifiedTitle("Bir Sevmek Bin Defa Ölmek Demekmiş - Feridun Hürel Albüm"), "Bir Sevmek Bin Defa Ölmek Demekmiş")
        XCTAssertNil(LyricsService.simplifiedTitle("Plain Title"), "nothing to strip")
    }
}
