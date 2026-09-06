import CoreAudio
import Foundation

/// One set of Core Audio listeners for the whole app: which device is the default output, and that
/// device's volume and mute. Observers are counted — the listeners exist only while somebody is
/// subscribed, so a module that is off costs nothing here — and every callback is delivered on the
/// main actor. Constructed once in the app delegate and handed to the modules that need it.
@MainActor
final class AudioOutputWatcher {
    enum Change: Equatable, Sendable {
        case device
        case volume
        case mute
    }

    /// The default output while listening; `nil` before the first subscriber or without a device.
    private(set) var device: AudioObjectID?

    private struct Observer {
        weak var owner: AnyObject?
        let handler: @MainActor (Change) -> Void
    }

    private var observers: [Observer] = []
    // Core Audio removes a listener only by the very block object that was added, so both are kept.
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var deviceAddresses: [AudioObjectPropertyAddress] = []
    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Starts the listeners on the first subscriber. A second registration by the same owner replaces the first.
    func addObserver(_ owner: AnyObject, _ handler: @escaping @MainActor (Change) -> Void) {
        observers.removeAll { $0.owner == nil || $0.owner === owner }
        observers.append(Observer(owner: owner, handler: handler))
        if systemListener == nil { install() }
    }

    /// Stops the listeners when the last subscriber leaves.
    func removeObserver(_ owner: AnyObject) {
        observers.removeAll { $0.owner == nil || $0.owner === owner }
        if observers.isEmpty { uninstall() }
    }

    /// Re-reads the default device and rebinds its listeners; the device change path does this on its own.
    func refresh() {
        guard systemListener != nil else { return }
        bindDevice()
    }

    // MARK: Listeners

    private func install() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.deviceChanged() }
        }
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioOutputDevice.systemObject, &address, DispatchQueue.main, listener)
        systemListener = listener
        bindDevice()
    }

    private func uninstall() {
        unbindDevice()
        if let systemListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioOutputDevice.systemObject, &address, DispatchQueue.main, systemListener)
        }
        systemListener = nil
        device = nil
    }

    private func bindDevice() {
        unbindDevice()
        guard let current = AudioOutputDevice.defaultOutput() else {
            device = nil
            return
        }
        device = current
        let addresses = AudioOutputDevice.volumeAddresses(current) + (AudioOutputDevice.hasMuteControl(current) ? [AudioOutputDevice.muteAddress] : [])
        guard !addresses.isEmpty else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] count, changed in
            let selectors = (0..<Int(count)).map { changed[$0].mSelector }
            MainActor.assumeIsolated { self?.deviceChanged(selectors: selectors) }
        }
        for var address in addresses {
            AudioObjectAddPropertyListenerBlock(current, &address, DispatchQueue.main, listener)
        }
        deviceListener = listener
        deviceAddresses = addresses
    }

    private func unbindDevice() {
        if let device, let deviceListener {
            for var address in deviceAddresses {
                AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, deviceListener)
            }
        }
        deviceListener = nil
        deviceAddresses = []
    }

    private func deviceChanged() {
        bindDevice()
        notify(.device)
    }

    private func deviceChanged(selectors: [AudioObjectPropertySelector]) {
        notify(selectors.contains(kAudioDevicePropertyMute) ? .mute : .volume)
    }

    private func notify(_ change: Change) {
        observers.removeAll { $0.owner == nil }
        for observer in observers {
            observer.handler(change)
        }
    }
}
