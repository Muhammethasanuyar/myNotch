import Foundation
import Observation
import os

/// The default output as a device: which one it is, and — for AirPods — what the registry says
/// about its battery. Listens through the shared `AudioOutputWatcher`; a device change is settled
/// for a moment (routes flap) before it is announced.
@MainActor
@Observable
final class AudioDeviceService {
    private(set) var output: AudioOutputInfo?
    private(set) var battery: AirPodsBattery?
    var connectPopups = true
    var disconnectPopups = false
    var batteryEnabled = true {
        didSet { if !batteryEnabled { battery = nil } }
    }
    /// A switch worth announcing; the module turns it into a popup.
    var onAlert: ((AudioDeviceAlert, AudioOutputInfo, AirPodsBattery?) -> Void)?
    var onChange: (() -> Void)?

    private let watcher: AudioOutputWatcher
    private let readRegistry: @Sendable () -> [AirPodsRegistryEntry]
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var batteryTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var isStarted = false
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "audio-device")

    init(watcher: AudioOutputWatcher, readRegistry: @escaping @Sendable () -> [AirPodsRegistryEntry] = { AirPodsBatteryReader.entries() }) {
        self.watcher = watcher
        self.readRegistry = readRegistry
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        watcher.addObserver(self) { [weak self] change in
            guard change == .device else { return }
            self?.scheduleSettle()
        }
        output = currentOutput()
        if let output, AudioDeviceRules.isBluetooth(output) { readBattery(for: output, announce: false) }
    }

    func stop() {
        isStarted = false
        watcher.removeObserver(self)
        settleTask?.cancel()
        settleTask = nil
        cancelBatteryReads()
        output = nil
        battery = nil
    }

    var outputLatency: TimeInterval? {
        output.flatMap { AudioOutputDevice.latency(of: $0.id) }
    }

    // MARK: Device changes

    private func currentOutput() -> AudioOutputInfo? {
        (watcher.device ?? AudioOutputDevice.defaultOutput()).flatMap(AudioOutputDevice.info)
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: AudioDeviceRules.settle)
            guard !Task.isCancelled else { return }
            self?.deviceSettled()
        }
    }

    private func deviceSettled() {
        let previous = output
        let current = currentOutput()
        guard previous != current else { return }
        output = current
        battery = nil
        cancelBatteryReads()
        onChange?()
        if let current, AudioDeviceRules.isBluetooth(current) {
            readBattery(for: current, announce: true, alert: AudioDeviceRules.shouldAnnounce(previous: previous, current: current, connectPopups: connectPopups, disconnectPopups: disconnectPopups))
            return
        }
        switch AudioDeviceRules.shouldAnnounce(previous: previous, current: current, connectPopups: connectPopups, disconnectPopups: disconnectPopups) {
        case .connected?:
            if let current { onAlert?(.connected, current, nil) }
        case .disconnected?:
            if let previous { onAlert?(.disconnected, previous, nil) }
        case nil:
            break
        }
    }

    // MARK: Battery

    /// Reads the registry now and again shortly after: AirPods publish their battery a beat late.
    /// The popup goes out with the first reading (even without a battery); later readings only
    /// update the card — never a second popup.
    private func readBattery(for device: AudioOutputInfo, announce: Bool, alert: AudioDeviceAlert? = nil) {
        guard batteryEnabled else {
            if announce, alert == .connected { onAlert?(.connected, device, nil) }
            return
        }
        let delays: [TimeInterval] = [0] + AudioDeviceRules.batteryRetryDelays
        for (index, delay) in delays.enumerated() {
            let read = readRegistry
            batteryTasks.append(Task { [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                let entries = await Task.detached(priority: .utility) { read() }.value
                guard !Task.isCancelled, let self, self.output == device else { return }
                let found = AudioDeviceRules.matchBattery(deviceName: device.name, deviceUID: device.uid, candidates: entries)
                if let found, found != self.battery {
                    self.battery = found
                    self.onChange?()
                }
                if index == 0, announce, alert == .connected {
                    self.onAlert?(.connected, device, found)
                }
            })
        }
    }

    private func cancelBatteryReads() {
        batteryTasks.forEach { $0.cancel() }
        batteryTasks.removeAll()
    }
}
