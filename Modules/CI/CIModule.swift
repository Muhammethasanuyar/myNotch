import SwiftUI

/// Builds in the notch: a hammer beside the housing while an Xcode build or a GitHub Actions run is
/// in flight, a popup when one finishes, and a card with the last few of each. Ships off: the
/// GitHub half runs the user's `gh` tool.
@MainActor
@Observable
final class CIModule: NotchModule {
    let id = "ci"
    let displayName = L("module.ci", "Builds")
    /// The newest and least proven signal: the popup is the product, the strip a bonus.
    let priority = 2

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle

    let service: CIService
    @ObservationIgnored private var context: ModuleContext?

    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "hammer.fill", isAvailable: !service.runs.isEmpty)]
    }

    init(service: CIService = CIService()) {
        self.service = service
    }

    func start(context: ModuleContext) {
        self.context = context
        service.onChange = { [weak self] in self?.updateActivity() }
        service.onFinished = { [weak self] run in
            guard let self else { return }
            self.context?.post(CIRules.event(for: run, moduleID: id))
        }
        service.start()
    }

    func stop() {
        service.onChange = nil
        service.onFinished = nil
        service.stop()
        activity = .idle
        context?.activityChanged()
    }

    private func updateActivity() {
        let next = CIRules.activity(service.runs)
        guard next != activity else { return }
        activity = next
        context?.activityChanged()
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(CICompactLeading())
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(CICompactTrailing(service: service))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(CIExpandedView(service: service))
    }
}
