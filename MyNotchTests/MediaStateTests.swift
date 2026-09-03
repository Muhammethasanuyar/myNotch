import XCTest
@testable import MyNotch

final class MediaStateTests: XCTestCase {
    private let sampledAt = Date(timeIntervalSince1970: 1_000_000)

    private func state(isPlaying: Bool, elapsed: TimeInterval = 30, duration: TimeInterval? = 240) -> MediaState {
        MediaState(
            providerID: "spotify",
            providerName: "Spotify",
            trackID: "t1",
            title: "Say It Ain't So",
            artist: "Weezer",
            album: "Weezer",
            isPlaying: isPlaying,
            duration: duration,
            elapsed: elapsed,
            elapsedAt: sampledAt,
            artwork: nil
        )
    }

    func testPlayheadIsExtrapolatedWhilePlaying() {
        let playing = state(isPlaying: true)
        XCTAssertEqual(playing.liveElapsed(at: sampledAt), 30, accuracy: 0.001)
        XCTAssertEqual(playing.liveElapsed(at: sampledAt.addingTimeInterval(12)), 42, accuracy: 0.001)
    }

    func testPlayheadIsFrozenWhilePaused() {
        let paused = state(isPlaying: false)
        XCTAssertEqual(paused.liveElapsed(at: sampledAt.addingTimeInterval(120)), 30, accuracy: 0.001)
    }

    func testPlayheadNeverRunsPastTheDuration() {
        let playing = state(isPlaying: true, elapsed: 235, duration: 240)
        XCTAssertEqual(playing.liveElapsed(at: sampledAt.addingTimeInterval(60)), 240, accuracy: 0.001)
        XCTAssertEqual(playing.progress(at: sampledAt.addingTimeInterval(60)), 1, accuracy: 0.001)
    }

    func testProgressIsZeroWithoutADuration() {
        XCTAssertEqual(state(isPlaying: true, duration: nil).progress(at: sampledAt.addingTimeInterval(30)), 0)
    }

    func testArtworkKeyIsPerProviderAndTrack() {
        XCTAssertEqual(state(isPlaying: true).artworkKey, "spotify|t1")
    }

    func testTogglingPlaybackFreezesThePlayheadWhereItIs() {
        let playing = state(isPlaying: true, elapsed: 30)
        let paused = playing.togglingPlayback(at: sampledAt.addingTimeInterval(10))

        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.elapsed, 40, accuracy: 0.001, "the playhead keeps the position it had reached")
        XCTAssertEqual(paused.liveElapsed(at: sampledAt.addingTimeInterval(60)), 40, accuracy: 0.001)
    }

    func testRepeatCyclesThroughEveryModeWhereThePlayerHasThem() {
        var current = state(isPlaying: true)
        XCTAssertEqual(current.repeatMode, .off)
        current.repeatMode = current.nextRepeatMode(hasModes: true)
        XCTAssertEqual(current.repeatMode, .all)
        current.repeatMode = current.nextRepeatMode(hasModes: true)
        XCTAssertEqual(current.repeatMode, .one)
        current.repeatMode = current.nextRepeatMode(hasModes: true)
        XCTAssertEqual(current.repeatMode, .off)
    }

    func testRepeatIsAPlainToggleWhereThePlayerHasNoModes() {
        var current = state(isPlaying: true)
        current.repeatMode = current.nextRepeatMode(hasModes: false)
        XCTAssertEqual(current.repeatMode, .all)
        current.repeatMode = current.nextRepeatMode(hasModes: false)
        XCTAssertEqual(current.repeatMode, .off)
    }

    func testRepeatSymbolMarksTheSingleTrackMode() {
        XCTAssertEqual(MediaRepeatMode.off.symbolName, "repeat")
        XCTAssertEqual(MediaRepeatMode.all.symbolName, "repeat")
        XCTAssertEqual(MediaRepeatMode.one.symbolName, "repeat.1")
        XCTAssertFalse(MediaRepeatMode.off.isOn)
        XCTAssertTrue(MediaRepeatMode.all.isOn)
    }

    func testScrubberFormatsTime() {
        XCTAssertEqual(MediaScrubber.time(0), "0:00")
        XCTAssertEqual(MediaScrubber.time(61), "1:01")
        XCTAssertEqual(MediaScrubber.time(600), "10:00")
        XCTAssertEqual(MediaScrubber.time(-5), "0:00")
    }
}
