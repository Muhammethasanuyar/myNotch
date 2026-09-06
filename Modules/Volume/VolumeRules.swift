import Foundation

/// The output level as the module reads it.
nonisolated struct VolumeSnapshot: Equatable, Sendable {
    /// 0…1, the device's own scale.
    let volume: Float
    let isMuted: Bool
    /// False for HDMI, optical and aggregate devices, which have no volume of their own.
    let hasVolumeControl: Bool
    let deviceName: String
}

/// One press of a sound key, decoded from a system-defined event.
nonisolated struct MediaKeyPress: Equatable, Sendable {
    enum Key: Int, Sendable {
        case soundUp = 0
        case soundDown = 1
        case mute = 7
    }

    let key: Key
    let isDown: Bool
    let isRepeat: Bool
}

/// Modifier keys held with a sound key.
nonisolated struct MediaKeyFlags: Equatable, Sendable {
    let shift: Bool
    let option: Bool

    /// Option+Shift adjusts in quarter steps, as macOS does.
    var isFine: Bool { shift && option }
    /// Shift alone flips the feedback sound, as macOS does.
    var flipsFeedback: Bool { shift && !option }
}

/// Pure decisions of the volume module: the step ladder, glyphs, key decoding, the swallow rule.
nonisolated enum VolumeRules {
    /// macOS moves the volume in sixteenths.
    static let step: Float = 1.0 / 16.0
    static let fineDivisor: Float = 4
    static let popupDuration: TimeInterval = 1.5
    /// A device change fires several listeners at once; they are folded into one reading.
    static let coalesce: Duration = .milliseconds(40)
    /// The sound macOS plays when "Play feedback when volume is changed" is on.
    static let feedbackSoundPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
    /// Absent on a fresh account, which means off.
    static let feedbackDefaultsKey = "com.apple.sound.beep.feedback"
    static let barSegmentCount = 16

    /// The next level on the ladder: snap to the grid, then one step (or a quarter of one) further.
    static func stepped(_ current: Float, up: Bool, fine: Bool) -> Float {
        let size = fine ? step / fineDivisor : step
        let index = (current / size).rounded()
        let next = (index + (up ? 1 : -1)) * size
        return min(max(next, 0), 1)
    }

    static func snapped(_ value: Float) -> Float {
        min(max((value / step).rounded() * step, 0), 1)
    }

    /// How many of the popup's segments light up.
    static func barSegments(_ volume: Float, isMuted: Bool, count: Int = barSegmentCount) -> Int {
        guard !isMuted else { return 0 }
        return min(count, max(0, Int((volume * Float(count)).rounded())))
    }

    static func symbolName(volume: Float, isMuted: Bool) -> String {
        if isMuted { return "speaker.slash.fill" }
        if volume <= 0 { return "speaker.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func levelText(_ snapshot: VolumeSnapshot, bundle: Bundle = .main) -> String {
        if !snapshot.hasVolumeControl {
            return String(localized: "volume.noControl", defaultValue: "No volume control", bundle: bundle)
        }
        if snapshot.isMuted {
            return String(localized: "volume.muted", defaultValue: "Muted", bundle: bundle)
        }
        return String(localized: "volume.percent", defaultValue: "\(Int((snapshot.volume * 100).rounded()))%", bundle: bundle)
    }

    /// The popup for a change worth showing: a level or mute change on a device that has them. The
    /// first reading after launch and a mere device rename announce nothing.
    static func event(previous: VolumeSnapshot?, current: VolumeSnapshot, moduleID: String, bundle: Bundle = .main) -> NotchEvent? {
        guard let previous, current.hasVolumeControl else { return nil }
        guard previous.volume != current.volume || previous.isMuted != current.isMuted else { return nil }
        return NotchEvent(
            moduleID: moduleID,
            title: levelText(current, bundle: bundle),
            symbolName: symbolName(volume: current.volume, isMuted: current.isMuted),
            duration: popupDuration
        )
    }

    /// Decodes `NSEvent.data1` of a system-defined event (subtype 8): the key code in the high
    /// half, the key state in the next byte (0x0A down, 0x0B up), the repeat flag in the low bit.
    /// Brightness (2, 3) and keyboard-backlight (21, 22) keys are not sound keys and yield `nil`.
    static func mediaKey(data1: Int) -> MediaKeyPress? {
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        guard let key = MediaKeyPress.Key(rawValue: keyCode) else { return nil }
        let state = (data1 & 0xFF00) >> 8
        return MediaKeyPress(key: key, isDown: state == 0x0A, isRepeat: data1 & 0x1 != 0)
    }

    /// A sound key is taken from the system only while the replacement is on and the device can
    /// actually be driven; otherwise the key passes through and macOS shows its own HUD.
    static func shouldSwallow(_ press: MediaKeyPress?, hudReplacement: Bool, hasVolumeControl: Bool) -> Bool {
        press != nil && hudReplacement && hasVolumeControl
    }

    /// `com.apple.sound.beep.feedback` in the global domain: 1 on, 0 off, missing = `defaultValue`.
    static func feedbackEnabled(globalDomain: [String: Any]?, defaultValue: Bool) -> Bool {
        guard let raw = globalDomain?[feedbackDefaultsKey] else { return defaultValue }
        if let number = raw as? NSNumber { return number.intValue != 0 }
        if let text = raw as? String {
            switch text.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return defaultValue
            }
        }
        return defaultValue
    }

    /// Shift flips the setting, as it does for macOS's own keys.
    static func shouldPlayFeedback(enabled: Bool, flags: MediaKeyFlags) -> Bool {
        enabled != flags.flipsFeedback
    }
}
