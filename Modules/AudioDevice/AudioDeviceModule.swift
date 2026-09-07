import SwiftUI

/// The output device in the notch: a popup when AirPods, headphones or a display take over the
/// sound (with the AirPods battery when the registry offers it), and a card that names the device,
/// its transport, latency and battery. Never live; the popup is the moment.
@MainActor
@Observable
final class AudioDeviceModule: NotchModule {
    let id = "audioDevice"
    let displayName = L("module.audioDevice", "Output device")
    /// Never consulted: the module is always idle.
    let priority = 1

    var isEnabled = true
    let activity: ModuleActivity = .idle

    let service: AudioDeviceService
    @ObservationIgnored private var context: ModuleContext?

    /// Offered while something other than the built-in speakers plays.
    var screens: [ModuleScreen] {
        let external = service.output.map(AudioDeviceRules.isExternal) ?? false
        return [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: service.output.map(AudioDeviceRules.symbolName) ?? "hifispeaker.fill", isAvailable: external)]
    }

    init(service: AudioDeviceService) {
        self.service = service
    }

    func start(context: ModuleContext) {
        self.context = context
        service.onAlert = { [weak self] alert, device, battery in
            guard let self else { return }
            switch alert {
            case .connected: self.context?.post(AudioDeviceRules.connectedEvent(device, battery: battery, moduleID: id))
            case .disconnected: self.context?.post(AudioDeviceRules.disconnectedEvent(device, moduleID: id))
            }
        }
        service.onChange = { [weak self] in self?.context?.activityChanged() }
        service.start()
    }

    func stop() {
        service.onAlert = nil
        service.onChange = nil
        service.stop()
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(AudioDeviceExpandedView(service: service))
    }
}
