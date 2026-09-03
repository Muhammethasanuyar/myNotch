import XCTest
@testable import MyNotch

final class MediaActivityRulesTests: XCTestCase {
    private func state(trackID: String, isPlaying: Bool = true, title: String = "Track") -> MediaState {
        MediaState(
            providerID: "spotify",
            providerName: "Spotify",
            trackID: trackID,
            title: title,
            artist: "Artist",
            album: "Album",
            isPlaying: isPlaying,
            duration: 200,
            elapsed: 0,
            elapsedAt: Date(),
            artwork: nil
        )
    }

    func testNothingLoadedKeepsTheModuleIdle() {
        XCTAssertEqual(MediaActivityRules.activity(for: nil, permission: .granted), .idle)
    }

    func testAPausedTrackStillEarnsTheCompactStrip() {
        XCTAssertEqual(MediaActivityRules.activity(for: state(trackID: "a", isPlaying: false), permission: .granted), .live)
    }

    func testDeniedPermissionKeepsTheModuleOutOfTheNotch() {
        XCTAssertEqual(MediaActivityRules.activity(for: state(trackID: "a"), permission: .denied), .idle)
    }

    func testTrackChangeIsAnnouncedOnlyWhenPlaying() {
        let first = state(trackID: "a")
        let second = state(trackID: "b")
        XCTAssertTrue(MediaActivityRules.shouldAnnounceTrackChange(previous: first, current: second))
        XCTAssertFalse(MediaActivityRules.shouldAnnounceTrackChange(previous: first, current: state(trackID: "b", isPlaying: false)))
    }

    func testPlayPauseOfTheSameTrackIsNotAnnounced() {
        let playing = state(trackID: "a")
        let paused = state(trackID: "a", isPlaying: false)
        XCTAssertFalse(MediaActivityRules.shouldAnnounceTrackChange(previous: paused, current: playing))
    }

    func testStartupIsQuiet() {
        XCTAssertFalse(MediaActivityRules.shouldAnnounceTrackChange(previous: nil, current: state(trackID: "a")))
        XCTAssertFalse(MediaActivityRules.shouldAnnounceTrackChange(previous: state(trackID: "a"), current: nil))
    }

    func testPollBacksOffWhenPaused() {
        XCTAssertEqual(MediaActivityRules.pollInterval(isPlaying: true), .seconds(15))
        XCTAssertEqual(MediaActivityRules.pollInterval(isPlaying: false), .seconds(60))
    }
}
