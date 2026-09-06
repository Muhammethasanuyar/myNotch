import SwiftUI

/// The battery in the notch: a bolt and the percentage while it charges or runs low, popups when
/// the adapter comes and goes or a threshold is crossed, and a gauge with the estimates when opened.
@MainActor
@Observable
final class BatteryModule: NotchModule {
    let id = "battery"
    let displayName = L("module.battery", "Battery")
    /// Above Claude's idle-time dashboard, below music: a charge never takes the strip from a song.
    let priority = 6

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle
    /// Plug/threshold popups; the gauge keeps its colours either way.
    var alertsEnabled = true

    let service: BatteryService
    @ObservationIgnored private var context: ModuleContext?
    @ObservationIgnored private var alertMemory = BatteryAlertMemory()

    /// One screen, offered only on a Mac that has a battery.
    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "battery.100percent.bolt", isAvailable: service.hasBattery)]
    }

    init(service: BatteryService = BatteryService()) {
        self.service = service
    }

    func start(context: ModuleContext) {
        self.context = context
        service.onChange = { [weak self] previous, current in
            self?.handleChange(previous: previous, current: current)
        }
        service.start()
        updateActivity()
    }

    func stop() {
        service.onChange = nil
        service.stop()
        activity = .idle
        context?.activityChanged()
    }

    private func handleChange(previous: BatterySnapshot?, current: BatterySnapshot) {
        let result = BatteryRules.alerts(previous: previous, current: current, thresholds: service.thresholds, memory: alertMemory)
        alertMemory = result.memory
        updateActivity()
        guard alertsEnabled else { return }
        for alert in result.alerts {
            context?.post(BatteryRules.event(for: alert, snapshot: current, moduleID: id))
        }
    }

    private func updateActivity() {
        let next = BatteryRules.activity(service.snapshot, thresholds: service.thresholds)
        guard next != activity else { return }
        activity = next
        context?.activityChanged()
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(BatteryCompactLeading(service: service))
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(BatteryCompactTrailing(service: service))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(BatteryExpandedView(service: service))
    }
}
