import CoreAudio
import Foundation

/// How long the sound takes to leave the Mac after the player thinks it has played it.
///
/// Built-in speakers add ~25 ms; Bluetooth headphones add 150–300 ms, enough for lyrics timed
/// to the player's position to run visibly ahead of what is heard. CoreAudio reports the pieces
/// (device latency, safety offset, buffer, stream latency) for the default output device; no
/// permission is involved and nothing is played or recorded.
nonisolated enum AudioOutputLatency {
    /// Seconds of output latency for the current default device, or `nil` when it cannot be read.
    static func current() -> TimeInterval? {
        guard let device = defaultOutputDevice(), let rate: Float64 = property(device, kAudioDevicePropertyNominalSampleRate), rate > 0 else {
            return nil
        }
        let latency: UInt32 = property(device, kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let safety: UInt32 = property(device, kAudioDevicePropertySafetyOffset, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let buffer: UInt32 = property(device, kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let stream: UInt32 = firstOutputStream(of: device).flatMap { property($0, kAudioStreamPropertyLatency) } ?? 0
        let frames = Double(latency) + Double(safety) + Double(buffer) + Double(stream)
        let seconds = frames / rate
        // Anything past two seconds is a misreport, not a device.
        return (0...2).contains(seconds) ? seconds : nil
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        let device: AudioObjectID? = property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
        return device.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    private static func firstOutputStream(of device: AudioObjectID) -> AudioStreamID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioStreamID>.size) else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else { return nil }
        return streams.first
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }
}
