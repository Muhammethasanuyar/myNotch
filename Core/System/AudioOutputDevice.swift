import CoreAudio
import Foundation

/// What the app needs to know about an output device.
nonisolated struct AudioOutputInfo: Equatable, Sendable {
    let id: AudioObjectID
    let uid: String?
    let name: String
    /// `kAudioDeviceTransportType*`.
    let transport: UInt32

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    var isBluetooth: Bool { transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE }
}

/// Pure Core Audio reads and writes on output devices: the default device, its name and transport,
/// volume and mute, output latency. No permission is involved and nothing is played or recorded.
/// Stateless; `AudioOutputWatcher` adds the listeners.
nonisolated enum AudioOutputDevice {
    /// 'vmvc' — the virtual main volume the Sound menu drives. Declared in AudioHardwareService.h as
    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`; spelled out to keep AudioToolbox out.
    static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func defaultOutput() -> AudioObjectID? {
        let device: AudioObjectID? = property(systemObject, kAudioHardwarePropertyDefaultOutputDevice)
        return device.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    static func info(_ device: AudioObjectID) -> AudioOutputInfo? {
        guard let name = string(device, kAudioObjectPropertyName) else { return nil }
        let transport: UInt32 = property(device, kAudioDevicePropertyTransportType) ?? kAudioDeviceTransportTypeUnknown
        return AudioOutputInfo(id: device, uid: string(device, kAudioDevicePropertyDeviceUID), name: name, transport: transport)
    }

    // MARK: Volume

    /// The volume properties a device may offer, in the order they are tried: the virtual main
    /// volume, the main-element scalar, then the first two channels.
    static func volumeAddresses(_ device: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let candidates = [
            AudioObjectPropertyAddress(mSelector: virtualMainVolume, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: 1),
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: 2)
        ]
        return candidates.filter { has(device, $0) }
    }

    static func hasVolumeControl(_ device: AudioObjectID) -> Bool {
        !volumeAddresses(device).isEmpty
    }

    /// 0…1, or `nil` for a device without a volume (HDMI, optical, aggregates).
    static func volume(_ device: AudioObjectID) -> Float? {
        let addresses = volumeAddresses(device)
        if let main = addresses.first(where: { $0.mElement == kAudioObjectPropertyElementMain }) {
            return property(device, main)
        }
        let channels: [Float] = addresses.compactMap { property(device, $0) }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float(channels.count)
    }

    @discardableResult
    static func setVolume(_ value: Float, on device: AudioObjectID) -> Bool {
        let clamped = min(max(value, 0), 1)
        let addresses = volumeAddresses(device).filter { isSettable(device, $0) }
        if let main = addresses.first(where: { $0.mElement == kAudioObjectPropertyElementMain }) {
            return set(device, main, clamped)
        }
        var written = false
        for address in addresses { written = set(device, address, clamped) || written }
        return written
    }

    // MARK: Mute

    static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static func hasMuteControl(_ device: AudioObjectID) -> Bool {
        has(device, muteAddress)
    }

    static func isMuted(_ device: AudioObjectID) -> Bool? {
        let value: UInt32? = property(device, muteAddress)
        return value.map { $0 != 0 }
    }

    @discardableResult
    static func setMuted(_ muted: Bool, on device: AudioObjectID) -> Bool {
        guard has(device, muteAddress), isSettable(device, muteAddress) else { return false }
        return set(device, muteAddress, UInt32(muted ? 1 : 0))
    }

    // MARK: Latency

    /// Seconds of output latency (device, safety offset, buffer, stream), or `nil` when unreadable.
    static func latency(of device: AudioObjectID) -> TimeInterval? {
        guard let rate: Float64 = property(device, kAudioDevicePropertyNominalSampleRate), rate > 0 else { return nil }
        let latency: UInt32 = property(device, kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let safety: UInt32 = property(device, kAudioDevicePropertySafetyOffset, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let buffer: UInt32 = property(device, kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let stream: UInt32 = firstOutputStream(of: device).flatMap { property($0, kAudioStreamPropertyLatency) } ?? 0
        let seconds = (Double(latency) + Double(safety) + Double(buffer) + Double(stream)) / rate
        // Anything past two seconds is a misreport, not a device.
        return (0...2).contains(seconds) ? seconds : nil
    }

    static func firstOutputStream(of device: AudioObjectID) -> AudioStreamID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioStreamID>.size) else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else { return nil }
        return streams.first
    }

    // MARK: Property plumbing

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        property(object, AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element))
    }

    static func property<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    static func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        var value = value
        return withUnsafePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), pointer) == noErr
        }
    }

    /// A `CFString` property, bridged; Core Audio hands the string over retained.
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
