import Foundation

/// One band of the meter: where it listens and which loudness it maps to the bar's range.
nonisolated struct BandSpec: Equatable, Sendable {
    let center: Double
    let q: Double
    /// dBFS at which the bar rests at the bottom…
    let floorDB: Double
    /// …and at which it touches the top.
    let ceilingDB: Double
}

/// A direct-form-I biquad; `process` runs once per sample on the audio thread, so no allocation.
nonisolated struct Biquad: Equatable, Sendable {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

nonisolated enum BiquadDesign {
    /// RBJ band-pass with 0 dB peak gain at `center`.
    static func bandpass(center: Double, q: Double, sampleRate: Double) -> Biquad {
        let w0 = 2 * Double.pi * center / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(
            b0: Float(alpha / a0),
            b1: 0,
            b2: Float(-alpha / a0),
            a1: Float(-2 * cos(w0) / a0),
            a2: Float((1 - alpha) / a0)
        )
    }
}

/// How the meter runs.
nonisolated enum EqualizerMode: Equatable, Sendable {
    /// Nothing plays: flat bars.
    case resting
    /// Playing, but no real levels: the autonomous Core Animation dance.
    case dancing
    /// Playing with the tap running: bars follow the sound.
    case live
}

nonisolated enum AudioMeterState: Equatable, Sendable {
    case off
    /// macOS before 14.2 has no process taps.
    case unsupported
    case starting
    case running
    /// The tap runs but hears nothing for a while — usually a permission that was refused.
    case silent
    case failed(OSStatus)
}

/// Pure decisions of the level meter: the bands, the dB windows and the envelope.
nonisolated enum AudioMeterRules {
    /// Six bands from bass to presence, each with its own loudness window so a quiet high band
    /// still moves; from spitfiresb/notch's tuning, documented in docs/harvest/spitfiresb-notch.md.
    static let bands: [BandSpec] = [
        BandSpec(center: 80, q: 2.4, floorDB: -44, ceilingDB: -14),
        BandSpec(center: 200, q: 2.4, floorDB: -46, ceilingDB: -16),
        BandSpec(center: 500, q: 2.4, floorDB: -50, ceilingDB: -20),
        BandSpec(center: 1200, q: 2.4, floorDB: -54, ceilingDB: -24),
        BandSpec(center: 3000, q: 2.4, floorDB: -58, ceilingDB: -28),
        BandSpec(center: 7000, q: 2.4, floorDB: -62, ceilingDB: -32)
    ]
    /// ~30 Hz: the eye cannot follow bars faster, and every publish is a Core Animation transaction.
    static let publishIntervalMilliseconds = 33
    /// A bar has to move at least this much to be worth a Core Animation transaction.
    static let changeThreshold: Float = 0.004
    static let restingLevel: Float = 0.14
    /// After this long without sound the tap counts as silent (permission refused, or muted).
    static let silenceTimeout: TimeInterval = 3
    static let attack: Float = 0.55
    static let release: Float = 0.18

    /// Bar height 0.10…1.0 from an RMS reading, through the band's dB window.
    static func level(rms: Float, band: BandSpec) -> Float {
        guard rms > 0 else { return 0.1 }
        let db = Double(20 * log10(rms))
        let fraction = (db - band.floorDB) / (band.ceilingDB - band.floorDB)
        return Float(min(1, max(0.1, 0.1 + fraction * 0.9)))
    }

    /// Fast up, slow down, so a beat lands and the bar falls away.
    static func envelope(previous: Float, target: Float) -> Float {
        let coefficient = target > previous ? attack : release
        return previous + (target - previous) * coefficient
    }

    /// Six bands onto however many bars there are: four bars average the ends together.
    static func barLevels(_ bands: [Float], barCount: Int) -> [Float] {
        switch (bands.count, barCount) {
        case (6, 6): return bands
        case (6, 4): return [(bands[0] + bands[1]) / 2, bands[2], bands[3], (bands[4] + bands[5]) / 2]
        default:
            assertionFailure("no mapping from \(bands.count) bands to \(barCount) bars")
            return Array(repeating: restingLevel, count: barCount)
        }
    }

    static func changed(_ a: [Float], _ b: [Float]) -> Bool {
        guard a.count == b.count else { return true }
        return zip(a, b).contains { abs($0 - $1) > changeThreshold }
    }

    static func mode(state: AudioMeterState, isPlaying: Bool) -> EqualizerMode {
        guard isPlaying else { return .resting }
        return state == .running ? .live : .dancing
    }
}
