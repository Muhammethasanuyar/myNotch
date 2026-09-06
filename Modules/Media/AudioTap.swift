import AudioToolbox
import CoreAudio
import Foundation
import os

/// A Core Audio process tap on everything the Mac plays, feeding six band-pass filters. The IO
/// block runs on the audio thread: no allocation, no blocking lock — it tries the lock and, on a
/// miss, drops that buffer's contribution rather than wait.
///
/// Privacy: the audio never leaves the process; the block reduces each buffer to six band energies
/// and discards the samples. macOS asks once for system-audio recording permission.
@available(macOS 14.2, *)
nonisolated final class AudioTapEngine: @unchecked Sendable {
    private let bands: [BandSpec]
    private var filters: [Biquad]
    private var sumSquares: [Float]
    private var sampleCount: Int = 0
    private var lock = os_unfair_lock()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.emre.mynotch.audio-tap", qos: .userInteractive)
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "audio-tap")

    init(bands: [BandSpec]) {
        self.bands = bands
        filters = bands.map { _ in Biquad(b0: 0, b1: 0, b2: 0, a1: 0, a2: 0) }
        sumSquares = Array(repeating: 0, count: bands.count)
    }

    deinit {
        stop()
    }

    /// Creates the tap, an aggregate device around the default output that carries it, and the IO
    /// proc; returns the sample rate the filters were designed for.
    func start() throws -> Double {
        stop()
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "MyNotch level meter"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create tap")
        tapID = tap

        let outputUID = try defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MyNotch level meter",
            kAudioAggregateDeviceUIDKey: "com.emre.mynotch.level-meter",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create aggregate device")
        self.aggregateID = aggregateID

        let format = try tapFormat()
        let sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
        let channels = Int(max(1, format.mChannelsPerFrame))
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        filters = bands.map { BiquadDesign.bandpass(center: $0.center, q: $0.q, sampleRate: sampleRate) }

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input, channels: channels, interleaved: interleaved)
        }
        try check(status, "create IO proc")
        self.procID = procID
        try check(AudioDeviceStart(aggregateID, procID), "start device")
        Self.log.info("audio tap running at \(sampleRate, privacy: .public) Hz, \(channels, privacy: .public) channel(s)")
        return sampleRate
    }

    func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// The RMS per band since the last drain; `false` when no audio arrived in between.
    func drainBands(into levels: inout [Float]) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard sampleCount > 0 else { return false }
        for index in bands.indices {
            levels[index] = (sumSquares[index] / Float(sampleCount)).squareRoot()
            sumSquares[index] = 0
        }
        sampleCount = 0
        return true
    }

    // MARK: Audio thread

    private func consume(_ list: UnsafePointer<AudioBufferList>, channels: Int, interleaved: Bool) {
        // Miss the lock rather than stall the audio thread; the meter publishes at 30 Hz anyway.
        guard os_unfair_lock_trylock(&lock) else { return }
        defer { os_unfair_lock_unlock(&lock) }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, let data = first.mData else { return }
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / (interleaved ? channels : 1)
        let samples = data.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            var mono: Float = 0
            if interleaved {
                for channel in 0..<channels { mono += samples[frame * channels + channel] }
            } else {
                for buffer in buffers {
                    guard let channelData = buffer.mData else { continue }
                    mono += channelData.assumingMemoryBound(to: Float.self)[frame]
                }
            }
            mono /= Float(channels)
            for index in filters.indices {
                let y = filters[index].process(mono)
                sumSquares[index] += y * y
            }
        }
        sampleCount += frames
    }

    // MARK: Core Audio plumbing

    private func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "default output")
        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        try check(withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, $0) }, "output UID")
        return uid as String
    }

    private func tapFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "tap format")
        return format
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else {
            Self.log.error("audio tap: \(step, privacy: .public) failed (\(status, privacy: .public))")
            stop()
            throw AudioTapError(step: step, status: status)
        }
    }
}

nonisolated struct AudioTapError: Error, Sendable {
    let step: String
    let status: OSStatus
}
