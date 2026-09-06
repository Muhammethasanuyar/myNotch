import AppKit
import ApplicationServices
import Observation
import os

/// The output level, read through the shared `AudioOutputWatcher`, and — when the user turns the
/// replacement on — the sound keys themselves through `MediaKeyTap`. Popups come from changes to
/// the reading, never from the key press, so a change made anywhere looks the same.
@MainActor
@Observable
final class VolumeService {
    enum TapState: Equatable, Sendable {
        case off
        case needsPermission
        case running
        case failed(String)
    }

    private(set) var snapshot: VolumeSnapshot?
    private(set) var tapState: TapState = .off
    /// How often the system disabled the tap and it came back; diagnostics for the pane.
    private(set) var tapReEnables = 0
    var popupsEnabled = true
    /// Take the sound keys from macOS (Accessibility permission required).
    var hudReplacement = false {
        didSet { if hudReplacement != oldValue { syncTap() } }
    }
    var onChange: ((VolumeSnapshot?, VolumeSnapshot) -> Void)?

    private let watcher: AudioOutputWatcher
    private let defaults: UserDefaults
    @ObservationIgnored private var tap: MediaKeyTap?
    @ObservationIgnored private var coalesceTask: Task<Void, Never>?
    @ObservationIgnored private var levelBeforeMute: Float = 0.5
    @ObservationIgnored private var permissionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private static let feedbackSound = NSSound(contentsOfFile: VolumeRules.feedbackSoundPath, byReference: true)
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "volume")

    init(watcher: AudioOutputWatcher, defaults: UserDefaults = .standard) {
        self.watcher = watcher
        self.defaults = defaults
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        watcher.addObserver(self) { [weak self] _ in self?.scheduleRefresh() }
        refresh()
        syncTap()
    }

    func stop() {
        isStarted = false
        watcher.removeObserver(self)
        coalesceTask?.cancel()
        coalesceTask = nil
        stopTap()
        stopPermissionWatch()
        tapState = .off
        snapshot = nil
    }

    // MARK: Reading

    /// Reads the default output afresh; a real change reaches `onChange`.
    func refresh() {
        guard let device = watcher.device ?? AudioOutputDevice.defaultOutput(), let info = AudioOutputDevice.info(device) else {
            snapshot = nil
            tap?.setSwallowing(false)
            return
        }
        let volume = AudioOutputDevice.volume(device)
        let current = VolumeSnapshot(
            volume: volume ?? 0,
            isMuted: AudioOutputDevice.isMuted(device) ?? (volume == 0),
            hasVolumeControl: volume != nil,
            deviceName: info.name
        )
        tap?.setSwallowing(current.hasVolumeControl)
        let previous = snapshot
        guard previous != current else { return }
        snapshot = current
        onChange?(previous, current)
    }

    private func scheduleRefresh() {
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(for: VolumeRules.coalesce)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: Writing

    func setVolume(_ value: Float) {
        guard let device = watcher.device ?? AudioOutputDevice.defaultOutput() else { return }
        if value > 0, AudioOutputDevice.isMuted(device) == true {
            AudioOutputDevice.setMuted(false, on: device)
        }
        AudioOutputDevice.setVolume(value, on: device)
        refresh()
    }

    func toggleMute() {
        guard let device = watcher.device ?? AudioOutputDevice.defaultOutput() else { return }
        if AudioOutputDevice.hasMuteControl(device) {
            AudioOutputDevice.setMuted(!(AudioOutputDevice.isMuted(device) ?? false), on: device)
        } else if let level = AudioOutputDevice.volume(device), level > 0 {
            // No mute property: remember the level and go to zero.
            levelBeforeMute = level
            AudioOutputDevice.setVolume(0, on: device)
        } else {
            AudioOutputDevice.setVolume(levelBeforeMute > 0 ? levelBeforeMute : 0.5, on: device)
        }
        refresh()
    }

    // MARK: Sound keys

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system's Accessibility prompt (once; later calls only re-check).
    func requestAccessibility() {
        // The key is `kAXTrustedCheckOptionPrompt`, a global var Swift 6 will not let us touch.
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        syncTap()
    }

    /// Brings the tap in line with the setting and the permission.
    func syncTap() {
        guard isStarted, hudReplacement else {
            stopTap()
            stopPermissionWatch()
            tapState = .off
            return
        }
        guard accessibilityTrusted else {
            stopTap()
            tapState = .needsPermission
            startPermissionWatch()
            return
        }
        stopPermissionWatch()
        if tap == nil { startTap() }
    }

    private func startTap() {
        let tap = MediaKeyTap()
        tap.setSwallowing(snapshot?.hasVolumeControl ?? false)
        tap.onPress = { [weak self] press, flags in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(press, flags: flags) }
            }
        }
        tap.onDisabled = { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.tapReEnables += 1 }
            }
        }
        do {
            try tap.start()
            self.tap = tap
            tapState = .running
        } catch {
            tapState = .failed(String(describing: error))
            Self.log.error("media key tap failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func stopTap() {
        tap?.stop()
        tap = nil
    }

    private func handle(_ press: MediaKeyPress, flags: MediaKeyFlags) {
        guard press.isDown, let current = snapshot, current.hasVolumeControl else { return }
        switch press.key {
        case .soundUp, .soundDown:
            setVolume(VolumeRules.stepped(current.isMuted ? 0 : current.volume, up: press.key == .soundUp, fine: flags.isFine))
        case .mute:
            toggleMute()
        }
        let enabled = VolumeRules.feedbackEnabled(globalDomain: defaults.persistentDomain(forName: UserDefaults.globalDomain), defaultValue: false)
        if VolumeRules.shouldPlayFeedback(enabled: enabled, flags: flags), let sound = Self.feedbackSound {
            sound.stop()
            sound.play()
        }
    }

    // MARK: Permission

    /// While the replacement is on but not yet allowed, notice the grant without polling: the
    /// system posts a distributed notification, and the app coming forward is worth a re-check.
    private func startPermissionWatch() {
        guard permissionObservers.isEmpty else { return }
        let check: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.syncTap() }
        }
        permissionObservers = [
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main, using: check),
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: check)
        ]
    }

    private func stopPermissionWatch() {
        for observer in permissionObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        permissionObservers = []
    }
}
