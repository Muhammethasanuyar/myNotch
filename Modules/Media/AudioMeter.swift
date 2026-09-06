import AppKit
import Observation
import os

/// Owns the process tap while the visualizer is on and music plays, reads its band energies at
/// 30 Hz on a utility queue, and hands bar levels to whoever is drawing them — only when a bar
/// moved enough to matter, so a silent room costs the main thread nothing.
@MainActor
@Observable
final class AudioMeter: EqualizerLevelFeed {
    private(set) var state: AudioMeterState = .off

    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var playing = false
    @ObservationIgnored private var engine: (any AnyObject & Sendable)?
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(owner: WeakBox, handler: @MainActor ([Float]) -> Void)] = []
    @ObservationIgnored private var lastLevels: [Float] = []
    @ObservationIgnored private var lastSound: Date?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    private static let debugDump = UserDefaults.standard.bool(forKey: "debugAudioMeter")

    // MARK: Switches

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        reconcile()
    }

    /// Pausing stops the tap after a short grace, so a skipped track does not tear it down.
    func setPlaying(_ on: Bool) {
        playing = on
        stopTask?.cancel()
        if on {
            reconcile()
        } else {
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.reconcile()
            }
        }
    }

    // MARK: Observers

    func addLevelObserver(_ owner: AnyObject, _ handler: @escaping @MainActor ([Float]) -> Void) {
        observers.removeAll { $0.owner.value == nil || $0.owner.value === owner }
        observers.append((WeakBox(owner), handler))
        reconcile()
    }

    func removeLevelObserver(_ owner: AnyObject) {
        observers.removeAll { $0.owner.value == nil || $0.owner.value === owner }
        reconcile()
    }

    // MARK: Lifecycle

    private var shouldRun: Bool {
        enabled && playing && !observers.isEmpty
    }

    private func reconcile() {
        if shouldRun {
            startIfNeeded()
        } else {
            stopEngine()
            state = enabled ? (state == .unsupported ? .unsupported : .off) : .off
        }
    }

    private func startIfNeeded() {
        guard timer == nil else { return }
        guard #available(macOS 14.2, *) else {
            state = .unsupported
            return
        }
        state = .starting
        let tap = AudioTapEngine(bands: AudioMeterRules.bands)
        do {
            _ = try tap.start()
        } catch let error as AudioTapError {
            state = .failed(error.status)
            scheduleRetry()
            return
        } catch {
            state = .failed(-1)
            return
        }
        engine = tap
        lastSound = Date()
        lastLevels = Array(repeating: AudioMeterRules.restingLevel, count: AudioMeterRules.bands.count)
        var envelope = lastLevels
        var bands = Array(repeating: Float(0), count: AudioMeterRules.bands.count)
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.emre.mynotch.audio-meter", qos: .utility))
        source.schedule(deadline: .now(), repeating: .milliseconds(AudioMeterRules.publishIntervalMilliseconds))
        source.setEventHandler { [weak self] in
            // Off the main actor: read the tap, shape the levels, and only then hop over if they moved.
            guard tap.drainBands(into: &bands) else {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.checkSilence() } }
                return
            }
            var levels = Array(repeating: Float(0), count: bands.count)
            for index in bands.indices {
                let target = AudioMeterRules.level(rms: bands[index], band: AudioMeterRules.bands[index])
                envelope[index] = AudioMeterRules.envelope(previous: envelope[index], target: target)
                levels[index] = envelope[index]
            }
            let heard = bands.contains { $0 > 0.0005 }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.publish(levels, heard: heard) } }
        }
        source.resume()
        timer = source
        state = .running
    }

    private func stopEngine() {
        timer?.cancel()
        timer = nil
        retryTask?.cancel()
        retryTask = nil
        if #available(macOS 14.2, *), let tap = engine as? AudioTapEngine {
            tap.stop()
        }
        engine = nil
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, shouldRun else { return }
            timer = nil
            startIfNeeded()
        }
    }

    private func publish(_ levels: [Float], heard: Bool) {
        if heard {
            lastSound = Date()
            if state == .silent { state = .running }
        } else {
            checkSilence()
        }
        guard AudioMeterRules.changed(levels, lastLevels) else { return }
        lastLevels = levels
        if Self.debugDump {
            Logger(subsystem: "com.emre.mynotch", category: "audio-tap").info("levels \(levels.map { String(format: "%.2f", $0) }.joined(separator: " "), privacy: .public)")
        }
        for observer in observers where observer.owner.value != nil {
            observer.handler(levels)
        }
    }

    /// A tap that hears nothing for a while is usually one the user refused permission for.
    private func checkSilence() {
        guard state == .running, let lastSound, Date().timeIntervalSince(lastSound) > AudioMeterRules.silenceTimeout else { return }
        state = .silent
    }
}

/// Lets the observer list hold its owners weakly.
private final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}
