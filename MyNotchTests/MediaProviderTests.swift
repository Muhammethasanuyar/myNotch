import XCTest
@testable import MyNotch

final class MediaProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let sep = MediaScript.separator

    private func joined(_ fields: [String]) -> String {
        fields.joined(separator: MediaScript.separator)
    }

    // MARK: Spotify

    func testSpotifyParsesAPlayingTrackAndConvertsMilliseconds() {
        let output = joined([
            "Say It Ain't So", "Weezer", "Weezer", "spotify:track:abc",
            "https://i.scdn.co/image/abc", "playing", "255000", "61.5"
        ])
        let state = SpotifyProvider.parse(output, at: now)

        XCTAssertEqual(state?.title, "Say It Ain't So")
        XCTAssertEqual(state?.artist, "Weezer")
        XCTAssertEqual(state?.trackID, "spotify:track:abc")
        XCTAssertEqual(state?.isPlaying, true)
        XCTAssertEqual(state?.duration ?? 0, 255, accuracy: 0.001, "Spotify reports milliseconds")
        XCTAssertEqual(state?.elapsed ?? 0, 61.5, accuracy: 0.001)
        XCTAssertEqual(state?.artwork, .url(URL(string: "https://i.scdn.co/image/abc")!))
    }

    func testSpotifyParsesAPausedTrack() {
        let output = joined(["Blue Monday", "New Order", "Power", "id", "", "paused", "450000", "0"])
        XCTAssertEqual(SpotifyProvider.parse(output, at: now)?.isPlaying, false)
    }

    func testSpotifyReturnsNilWhenStoppedOrMalformed() {
        XCTAssertNil(SpotifyProvider.parse("", at: now))
        XCTAssertNil(SpotifyProvider.parse("only\(sep)three\(sep)fields", at: now))
        XCTAssertNil(SpotifyProvider.parse(joined(["", "a", "b", "c", "", "playing", "1000", "0"]), at: now))
    }

    func testSpotifyFallsBackToArtistAndTitleWhenThereIsNoTrackID() {
        let output = joined(["Local File", "Someone", "Album", "", "", "playing", "1000", "0"])
        XCTAssertEqual(SpotifyProvider.parse(output, at: now)?.trackID, "Someone|Local File")
    }

    func testSpotifyIgnoresAZeroDuration() {
        let output = joined(["Live Stream", "Radio", "", "id", "", "playing", "0", "12"])
        XCTAssertNil(SpotifyProvider.parse(output, at: now)?.duration)
    }

    func testSpotifyCommandScripts() {
        XCTAssertEqual(SpotifyProvider.script(for: .playPause), "tell application \"Spotify\" to playpause")
        XCTAssertEqual(SpotifyProvider.script(for: .next), "tell application \"Spotify\" to next track")
        XCTAssertEqual(SpotifyProvider.script(for: .previous), "tell application \"Spotify\" to previous track")
        XCTAssertEqual(SpotifyProvider.script(for: .seek(42)), "tell application \"Spotify\" to set player position to 42.0")
        XCTAssertEqual(SpotifyProvider.script(for: .seek(-3)), "tell application \"Spotify\" to set player position to 0.0")
    }

    // MARK: Apple Music

    func testAppleMusicParsesSecondsNotMilliseconds() {
        let output = joined(["Teardrop", "Massive Attack", "Mezzanine", "12345", "playing", "330", "12"])
        let state = AppleMusicProvider.parse(output, at: now)

        XCTAssertEqual(state?.providerID, "appleMusic")
        XCTAssertEqual(state?.title, "Teardrop")
        XCTAssertEqual(state?.trackID, "12345")
        XCTAssertEqual(state?.duration ?? 0, 330, accuracy: 0.001)
        XCTAssertEqual(state?.elapsed ?? 0, 12, accuracy: 0.001)
        XCTAssertNil(state?.artwork, "Music has no artwork URL; the file is written on demand")
    }

    func testAppleMusicReturnsNilWhenStopped() {
        XCTAssertNil(AppleMusicProvider.parse("", at: now))
        XCTAssertNil(AppleMusicProvider.parse(joined(["a", "b"]), at: now))
    }

    func testAppleMusicArtworkScriptTargetsTheGivenPath() {
        let script = AppleMusicProvider.artworkScript(destination: "/tmp/art.bin")
        XCTAssertTrue(script.contains("POSIX file \"/tmp/art.bin\""))
        XCTAssertTrue(script.contains("close access handle"))
    }

    // MARK: Shared

    func testFieldSplittingRejectsUnexpectedShapes() {
        XCTAssertNil(MediaScript.fields("", expected: 3))
        XCTAssertNil(MediaScript.fields("a\(sep)b", expected: 3))
        XCTAssertEqual(MediaScript.fields("a\(sep)b\(sep)c", expected: 3), ["a", "b", "c"])
    }

    func testAppleScriptErrorMapping() {
        XCTAssertEqual(AppleScriptRunner.mapError(status: 1, message: "error -1743: not authorized"), .permissionDenied)
        XCTAssertEqual(AppleScriptRunner.mapError(status: 1, message: "Application isn't running (-600)"), .appUnavailable)
        XCTAssertEqual(
            AppleScriptRunner.mapError(status: 2, message: "syntax error"),
            .failed(status: 2, message: "syntax error")
        )
    }
}
