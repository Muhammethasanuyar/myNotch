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

    func testScrubberFormatsTime() {
        XCTAssertEqual(MediaScrubber.time(0), "0:00")
        XCTAssertEqual(MediaScrubber.time(61), "1:01")
        XCTAssertEqual(MediaScrubber.time(600), "10:00")
        XCTAssertEqual(MediaScrubber.time(-5), "0:00")
    }
}
