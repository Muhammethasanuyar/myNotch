import SwiftUI

/// Now playing in the notch: artwork and a level meter beside the housing, full transport controls
/// when expanded, and a popup when the track changes.
@MainActor
@Observable
final class MediaModule: NotchModule {
    let id = "media"
    let displayName = "Media"
    /// Above the demo module: when music plays it should own the strip.
    let priority = 10

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle

    let controller: MediaController
    @ObservationIgnored private var context: ModuleContext?

    init(controller: MediaController = MediaController()) {
        self.controller = controller
    }

    func start(context: ModuleContext) {
        self.context = context
        controller.onStateChange = { [weak self] previous, current in
            self?.handleStateChange(previous: previous, current: current)
        }
        controller.start()
    }

    func stop() {
        controller.onStateChange = nil
        controller.stop()
        activity = .idle
        context?.activityChanged()
    }

    private func handleStateChange(previous: MediaState?, current: MediaState?) {
        let newActivity = MediaActivityRules.activity(for: current, permission: controller.permission)
        if newActivity != activity {
            activity = newActivity
            context?.activityChanged()
        }
        guard MediaActivityRules.shouldAnnounceTrackChange(previous: previous, current: current),
              let current else { return }
        context?.post(NotchEvent(
            moduleID: id,
            title: current.title,
            detail: current.artist,
            symbolName: "music.note",
            duration: 2.5
        ))
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(MediaCompactLeading(controller: controller, namespace: namespace))
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(MediaCompactTrailing(controller: controller))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(MediaExpandedView(controller: controller, namespace: namespace))
    }

    func popupView(for event: NotchEvent, namespace: Namespace.ID) -> AnyView? {
        AnyView(MediaPopupView(controller: controller, event: event))
    }

    /// Shared id for the artwork that morphs between compact and expanded.
    static let artworkID = "media.artwork"
}
