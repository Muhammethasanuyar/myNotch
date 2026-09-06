import CoreAudio
import Foundation

/// How long the sound takes to leave the Mac after the player thinks it has played it.
///
/// Built-in speakers add ~25 ms; Bluetooth headphones add 150–300 ms, enough for lyrics timed
/// to the player's position to run visibly ahead of what is heard. The pieces (device latency,
/// safety offset, buffer, stream latency) come from `AudioOutputDevice`; no permission is
/// involved and nothing is played or recorded.
nonisolated enum AudioOutputLatency {
    /// Seconds of output latency for the current default device, or `nil` when it cannot be read.
    static func current() -> TimeInterval? {
        AudioOutputDevice.defaultOutput().flatMap(AudioOutputDevice.latency(of:))
    }
}
