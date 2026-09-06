import SwiftUI

/// The output level in the notch: a short popup whenever it changes and, when the user turns the
/// replacement on, the sound keys themselves so macOS's own HUD stays away. Never live — the
/// module owns nothing but the moment of a change.
@MainActor
@Observable
final class VolumeModule: NotchModule {
    let id = "volume"
    let displayName = L("module.volume", "Volume")
    /// Never consulted: the module is always idle and speaks only through popups.
    let priority = 1

    var isEnabled = true
    let activity: ModuleActivity = .idle

    let service: VolumeService
    @ObservationIgnored private var context: ModuleContext?

    /// The card is about the replacement (level, mute, device, permission); without it the popup is the whole story.
    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "speaker.wave.2.fill", isAvailable: service.hudReplacement)]
    }

    init(service: VolumeService) {
        self.service = service
    }

    func start(context: ModuleContext) {
        self.context = context
        service.onChange = { [weak self] previous, current in
            guard let self, service.popupsEnabled else { return }
            if let event = VolumeRules.event(previous: previous, current: current, moduleID: id) {
                self.context?.post(event)
            }
        }
        service.start()
    }

    func stop() {
        service.onChange = nil
        service.stop()
    }

    // MARK: Views

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(VolumeExpandedView(service: service))
    }

    func popupView(for event: NotchEvent, namespace: Namespace.ID) -> AnyView? {
        guard event.moduleID == id else { return nil }
        return AnyView(VolumePopupView(service: service))
    }
}
