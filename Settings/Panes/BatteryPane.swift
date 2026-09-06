import SwiftUI

/// The battery's current reading and where its warnings sit.
struct BatteryPane: View {
    @Bindable var store: SettingsStore
    let module: BatteryModule?

    var body: some View {
        if let module {
            content(service: module.service)
        } else {
            ContentUnavailableView(L("settings.battery.missing", "The battery module is not registered."), systemImage: "battery.100percent.bolt")
        }
    }

    private func content(service: BatteryService) -> some View {
        SettingsForm {
            Section(L("settings.battery.status", "Status")) {
                if let snapshot = service.snapshot {
                    StatusRow(
                        tone: snapshot.isCharging || snapshot.isPluggedIn ? .ok : (BatteryRules.level(snapshot, thresholds: service.thresholds) > 0 ? .attention : .neutral),
                        title: "\(BatteryRules.percentText(snapshot)) · \(BatteryRules.statusTitle(snapshot))",
                        detail: BatteryRules.estimate(snapshot)
                    )
                } else {
                    StatusRow(tone: .neutral, title: L("settings.battery.none", "No internal battery"), detail: L("settings.battery.none.help", "The module stays idle on this Mac."))
                }
            }

            Section(L("settings.battery.alerts", "Alerts")) {
                Toggle(L("settings.battery.alerts.enabled", "Popups when the adapter comes and goes or the battery runs low"), isOn: $store.batteryAlertsEnabled)
                    .toggleStyle(.switch)
                ValueSlider(
                    title: L("settings.battery.alerts.low", "Low at"),
                    value: $store.batteryLowThreshold,
                    range: SettingsRules.batteryLowRange,
                    step: 0.05,
                    format: SettingsFormat.percent
                )
                ValueSlider(
                    title: L("settings.battery.alerts.critical", "Critical at"),
                    value: $store.batteryCriticalThreshold,
                    range: SettingsRules.batteryCriticalRange,
                    step: 0.05,
                    format: SettingsFormat.percent
                )
                HStack {
                    Button(L("settings.battery.alerts.reset", "Reset thresholds")) {
                        store.resetBatteryThresholds()
                    }
                    .controlSize(.small)
                    Spacer()
                }
                SettingsFootnote(L("settings.battery.alerts.help", "Each level announces itself once per discharge; plugging in re-arms them. The gauge in the notch turns orange and red at the same points."))
            }
        }
    }
}
