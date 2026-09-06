import XCTest
@testable import MyNotch

final class VolumeRulesTests: XCTestCase {
    private func snapshot(_ volume: Float, muted: Bool = false, control: Bool = true) -> VolumeSnapshot {
        VolumeSnapshot(volume: volume, isMuted: muted, hasVolumeControl: control, deviceName: "Speakers")
    }

    func testTheLadderMovesInSixteenthsAndStopsAtTheEnds() {
        XCTAssertEqual(VolumeRules.stepped(0.5, up: true, fine: false), 0.5625, accuracy: 0.0001)
        XCTAssertEqual(VolumeRules.stepped(0.5, up: false, fine: false), 0.4375, accuracy: 0.0001)
        XCTAssertEqual(VolumeRules.stepped(0.53, up: true, fine: false), 0.5625, accuracy: 0.0001, "an off-grid level snaps first")
        XCTAssertEqual(VolumeRules.stepped(1, up: true, fine: false), 1)
        XCTAssertEqual(VolumeRules.stepped(0, up: false, fine: false), 0)
        XCTAssertEqual(VolumeRules.stepped(0.5, up: true, fine: true), 0.515625, accuracy: 0.0001, "a fine step is a quarter of one")
        XCTAssertEqual(VolumeRules.snapped(0.49), 0.5, accuracy: 0.0001)
        XCTAssertEqual(VolumeRules.snapped(VolumeRules.snapped(0.49)), VolumeRules.snapped(0.49), "snapping is idempotent")
        XCTAssertEqual(VolumeRules.snapped(1.4), 1)
    }

    func testGlyphsAndSegments() {
        XCTAssertEqual(VolumeRules.symbolName(volume: 0.5, isMuted: true), "speaker.slash.fill")
        XCTAssertEqual(VolumeRules.symbolName(volume: 0, isMuted: false), "speaker.fill")
        XCTAssertEqual(VolumeRules.symbolName(volume: 0.2, isMuted: false), "speaker.wave.1.fill")
        XCTAssertEqual(VolumeRules.symbolName(volume: 0.5, isMuted: false), "speaker.wave.2.fill")
        XCTAssertEqual(VolumeRules.symbolName(volume: 0.9, isMuted: false), "speaker.wave.3.fill")
        XCTAssertEqual(VolumeRules.barSegments(0.5, isMuted: false), 8)
        XCTAssertEqual(VolumeRules.barSegments(1, isMuted: false), 16)
        XCTAssertEqual(VolumeRules.barSegments(0.8, isMuted: true), 0)
        let bundle = Bundle(for: VolumeRulesTests.self)
        XCTAssertEqual(VolumeRules.levelText(snapshot(0.5), bundle: bundle), "50%")
        XCTAssertEqual(VolumeRules.levelText(snapshot(0.5, muted: true), bundle: bundle), "Muted")
        XCTAssertEqual(VolumeRules.levelText(snapshot(0, control: false), bundle: bundle), "No volume control")
    }

    func testOnlyRealChangesBecomePopups() {
        let bundle = Bundle(for: VolumeRulesTests.self)
        XCTAssertNil(VolumeRules.event(previous: nil, current: snapshot(0.5), moduleID: "volume", bundle: bundle), "the first reading is not news")
        XCTAssertNil(VolumeRules.event(previous: snapshot(0.5), current: snapshot(0.5), moduleID: "volume", bundle: bundle))
        let renamed = VolumeSnapshot(volume: 0.5, isMuted: false, hasVolumeControl: true, deviceName: "AirPods")
        XCTAssertNil(VolumeRules.event(previous: snapshot(0.5), current: renamed, moduleID: "volume", bundle: bundle), "a device rename alone says nothing")
        let up = VolumeRules.event(previous: snapshot(0.5), current: snapshot(0.5625), moduleID: "volume", bundle: bundle)
        XCTAssertEqual(up?.title, "56%")
        XCTAssertEqual(up?.symbolName, "speaker.wave.2.fill")
        XCTAssertEqual(up?.duration, 1.5)
        let muted = VolumeRules.event(previous: snapshot(0.5), current: snapshot(0.5, muted: true), moduleID: "volume", bundle: bundle)
        XCTAssertEqual(muted?.title, "Muted")
        XCTAssertNil(VolumeRules.event(previous: snapshot(0, control: false), current: snapshot(0.3, control: false), moduleID: "volume", bundle: bundle), "a device without volume never pops up")
    }

    func testMediaKeyDecoding() {
        func data1(key: Int, down: Bool, repeating: Bool = false) -> Int {
            (key << 16) | ((down ? 0x0A : 0x0B) << 8) | (repeating ? 1 : 0)
        }
        XCTAssertEqual(VolumeRules.mediaKey(data1: data1(key: 0, down: true)), MediaKeyPress(key: .soundUp, isDown: true, isRepeat: false))
        XCTAssertEqual(VolumeRules.mediaKey(data1: data1(key: 1, down: false)), MediaKeyPress(key: .soundDown, isDown: false, isRepeat: false))
        XCTAssertEqual(VolumeRules.mediaKey(data1: data1(key: 7, down: true, repeating: true)), MediaKeyPress(key: .mute, isDown: true, isRepeat: true))
        for other in [2, 3, 21, 22, 16, 19, 20] {
            XCTAssertNil(VolumeRules.mediaKey(data1: data1(key: other, down: true)), "key \(other) is not a sound key and must pass through")
        }
    }

    func testTheSwallowRule() {
        let press = MediaKeyPress(key: .soundUp, isDown: true, isRepeat: false)
        XCTAssertTrue(VolumeRules.shouldSwallow(press, hudReplacement: true, hasVolumeControl: true))
        XCTAssertFalse(VolumeRules.shouldSwallow(press, hudReplacement: false, hasVolumeControl: true))
        XCTAssertFalse(VolumeRules.shouldSwallow(press, hudReplacement: true, hasVolumeControl: false), "HDMI keeps the system's own behaviour")
        XCTAssertFalse(VolumeRules.shouldSwallow(nil, hudReplacement: true, hasVolumeControl: true))
    }

    func testFeedbackSetting() {
        XCTAssertFalse(VolumeRules.feedbackEnabled(globalDomain: nil, defaultValue: false))
        XCTAssertTrue(VolumeRules.feedbackEnabled(globalDomain: [:], defaultValue: true))
        XCTAssertTrue(VolumeRules.feedbackEnabled(globalDomain: [VolumeRules.feedbackDefaultsKey: 1], defaultValue: false))
        XCTAssertFalse(VolumeRules.feedbackEnabled(globalDomain: [VolumeRules.feedbackDefaultsKey: 0], defaultValue: true))
        XCTAssertTrue(VolumeRules.feedbackEnabled(globalDomain: [VolumeRules.feedbackDefaultsKey: true], defaultValue: false))
        XCTAssertTrue(VolumeRules.feedbackEnabled(globalDomain: [VolumeRules.feedbackDefaultsKey: "banana"], defaultValue: true), "a value of the wrong type falls back")
        XCTAssertTrue(VolumeRules.shouldPlayFeedback(enabled: false, flags: MediaKeyFlags(shift: true, option: false)))
        XCTAssertFalse(VolumeRules.shouldPlayFeedback(enabled: true, flags: MediaKeyFlags(shift: true, option: false)))
        XCTAssertTrue(VolumeRules.shouldPlayFeedback(enabled: true, flags: MediaKeyFlags(shift: true, option: true)), "Option+Shift is the fine step, not the feedback flip")
        XCTAssertTrue(MediaKeyFlags(shift: true, option: true).isFine)
        XCTAssertFalse(MediaKeyFlags(shift: true, option: false).isFine)
    }
}
