import XCTest
@testable import MyNotch

final class AudioMeterTests: XCTestCase {
    private func rms(of filter: Biquad, frequency: Double, sampleRate: Double = 44_100, samples: Int = 8192) -> Float {
        var filter = filter
        var sum: Float = 0
        for n in 0..<samples {
            let x = Float(sin(2 * Double.pi * frequency * Double(n) / sampleRate))
            let y = filter.process(x)
            if n >= samples / 2 { sum += y * y }   // let the filter settle first
        }
        return (sum / Float(samples / 2)).squareRoot()
    }

    func testBandpassPrefersItsCentre() {
        let filter = BiquadDesign.bandpass(center: 1200, q: 2.4, sampleRate: 44_100)
        let centre = rms(of: filter, frequency: 1200)
        let farBelow = rms(of: filter, frequency: 150)
        let farAbove = rms(of: filter, frequency: 9600)
        XCTAssertGreaterThan(20 * log10(centre / farBelow), 20, "three octaves down is at least 20 dB quieter")
        XCTAssertGreaterThan(20 * log10(centre / farAbove), 20)
        XCTAssertEqual(centre, 0.707, accuracy: 0.05, "a full-scale sine passes at about 0 dB")
        var dc = filter
        var last: Float = 0
        for _ in 0..<4096 { last = dc.process(1) }
        XCTAssertEqual(last, 0, accuracy: 0.001, "DC does not pass")
    }

    func testLevelWindowsAndClamping() {
        let band = AudioMeterRules.bands[0]
        XCTAssertEqual(AudioMeterRules.level(rms: 0, band: band), 0.1)
        XCTAssertEqual(AudioMeterRules.level(rms: 0.0001, band: band), 0.1, "far below the floor rests at the bottom")
        XCTAssertEqual(AudioMeterRules.level(rms: 1, band: band), 1, "above the ceiling touches the top")
        let quiet = AudioMeterRules.level(rms: 0.02, band: band)
        let loud = AudioMeterRules.level(rms: 0.1, band: band)
        XCTAssertGreaterThan(loud, quiet)
        XCTAssertTrue((0.1...1).contains(quiet) && (0.1...1).contains(loud))
    }

    func testEnvelopeRisesFastAndFallsSlowly() {
        var level: Float = 0.1
        var rises = 0
        while level < 0.95 { level = AudioMeterRules.envelope(previous: level, target: 1); rises += 1 }
        var falls = 0
        while level > 0.15 { level = AudioMeterRules.envelope(previous: level, target: 0.1); falls += 1 }
        XCTAssertLessThanOrEqual(rises, 4)
        XCTAssertGreaterThanOrEqual(falls, 8)
        XCTAssertEqual(AudioMeterRules.envelope(previous: 0.5, target: 0.5), 0.5)
    }

    func testBarMappingAndChangeThreshold() {
        let bands: [Float] = [0.2, 0.4, 0.6, 0.8, 1.0, 0.0]
        XCTAssertEqual(AudioMeterRules.barLevels(bands, barCount: 4), [0.3, 0.6, 0.8, 0.5])
        XCTAssertEqual(AudioMeterRules.barLevels(bands, barCount: 6), bands)
        XCTAssertFalse(AudioMeterRules.changed([0.5, 0.5], [0.503, 0.5]))
        XCTAssertTrue(AudioMeterRules.changed([0.5, 0.5], [0.505, 0.5]))
        XCTAssertTrue(AudioMeterRules.changed([0.5], [0.5, 0.5]))
    }

    func testModeTable() {
        XCTAssertEqual(AudioMeterRules.mode(state: .running, isPlaying: true), .live)
        XCTAssertEqual(AudioMeterRules.mode(state: .silent, isPlaying: true), .dancing)
        XCTAssertEqual(AudioMeterRules.mode(state: .failed(-1), isPlaying: true), .dancing)
        XCTAssertEqual(AudioMeterRules.mode(state: .off, isPlaying: true), .dancing)
        XCTAssertEqual(AudioMeterRules.mode(state: .unsupported, isPlaying: true), .dancing)
        XCTAssertEqual(AudioMeterRules.mode(state: .running, isPlaying: false), .resting)
    }
}
