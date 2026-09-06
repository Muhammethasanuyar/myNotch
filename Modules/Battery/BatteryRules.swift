import Foundation
import IOKit.ps
import SwiftUI

/// Pure decisions of the battery module, so they can be tested with plain dictionaries.
nonisolated enum BatteryRules {
    /// Reads one power source description (`IOPSGetPowerSourceDescription`); `nil` when it is not
    /// a present internal battery — a desktop Mac, or a UPS.
    static func parse(powerSource: [String: Any], lowPowerMode: Bool) -> BatterySnapshot? {
        guard powerSource[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              powerSource[kIOPSIsPresentKey] as? Bool ?? true else { return nil }
        let current = powerSource[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = powerSource[kIOPSMaxCapacityKey] as? Int ?? 100
        let percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
        let isCharging = powerSource[kIOPSIsChargingKey] as? Bool ?? false
        let isPluggedIn = powerSource[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        return BatterySnapshot(
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            percentage: min(100, Swift.max(0, percentage)),
            timeToFull: isCharging ? minutes(powerSource[kIOPSTimeToFullChargeKey]) : nil,
            timeToEmpty: isPluggedIn ? nil : minutes(powerSource[kIOPSTimeToEmptyKey]),
            isLowPowerMode: lowPowerMode
        )
    }

    /// IOKit reports minutes, with `-1` while it is still working the estimate out.
    private static func minutes(_ value: Any?) -> TimeInterval? {
        guard let minutes = value as? Int, minutes >= 0 else { return nil }
        return TimeInterval(minutes) * 60
    }

    /// Worth a place in the strip while the battery charges or runs low; otherwise it stays out
    /// of the way — a full battery on mains has nothing to say.
    static func activity(_ snapshot: BatterySnapshot?, thresholds: BatteryThresholds) -> ModuleActivity {
        guard let snapshot else { return .idle }
        if snapshot.isCharging && !snapshot.isFull { return .live }
        if !snapshot.isPluggedIn && fraction(snapshot) <= thresholds.low { return .live }
        return .idle
    }

    /// 0 fine, 1 low, 2 critical — the gauge's colour.
    static func level(_ snapshot: BatterySnapshot, thresholds: BatteryThresholds) -> Int {
        guard !snapshot.isPluggedIn else { return 0 }
        let value = fraction(snapshot)
        if value <= thresholds.critical { return 2 }
        if value <= thresholds.low { return 1 }
        return 0
    }

    static func fraction(_ snapshot: BatterySnapshot) -> Double {
        Double(snapshot.percentage) / 100
    }

    /// The alerts a change deserves, and the memory that keeps each one-shot alert to once per
    /// crossing. Plugging in re-arms the low alerts; unplugging re-arms the full one.
    static func alerts(
        previous: BatterySnapshot?,
        current: BatterySnapshot,
        thresholds: BatteryThresholds,
        memory: BatteryAlertMemory
    ) -> (alerts: [BatteryAlert], memory: BatteryAlertMemory) {
        var memory = memory
        var alerts: [BatteryAlert] = []
        let fraction = fraction(current)

        if let previous {
            if current.isPluggedIn != previous.isPluggedIn {
                alerts.append(current.isPluggedIn ? .pluggedIn : .unplugged)
            }
            if current.isLowPowerMode != previous.isLowPowerMode {
                alerts.append(current.isLowPowerMode ? .lowPowerModeOn : .lowPowerModeOff)
            }
        }

        if current.isPluggedIn {
            memory.announcedLow = false
            memory.announcedCritical = false
            if current.isFull, !memory.announcedFull {
                // Only a charge that finishes while watched is worth a word; plugging in a battery
                // that is already full says nothing new.
                if let previous, previous.isPluggedIn, !previous.isFull {
                    alerts.append(.full)
                }
                memory.announcedFull = true
            }
        } else {
            memory.announcedFull = false
            if fraction <= thresholds.critical {
                if !memory.announcedCritical {
                    alerts.append(.critical)
                    memory.announcedCritical = true
                    memory.announcedLow = true
                }
            } else if fraction <= thresholds.low {
                if !memory.announcedLow {
                    alerts.append(.low)
                    memory.announcedLow = true
                }
                if fraction > thresholds.critical + 0.05 { memory.announcedCritical = false }
            } else {
                if fraction > thresholds.low + 0.05 { memory.announcedLow = false }
                memory.announcedCritical = false
            }
        }
        return (alerts, memory)
    }

    // MARK: Text

    /// "1h 20m" — hours and minutes, the way the Claude card writes remaining time.
    static func formatTime(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2).locale(locale))
    }

    static func statusTitle(_ snapshot: BatterySnapshot, bundle: Bundle = .main) -> String {
        if snapshot.isFull {
            return String(localized: "battery.status.full", defaultValue: "Fully charged", bundle: bundle)
        }
        if snapshot.isCharging {
            return String(localized: "battery.status.charging", defaultValue: "Charging", bundle: bundle)
        }
        if snapshot.isPluggedIn {
            return String(localized: "battery.status.plugged", defaultValue: "On power, not charging", bundle: bundle)
        }
        return String(localized: "battery.status.onBattery", defaultValue: "On battery", bundle: bundle)
    }

    /// "1h 20m to full" / "4h 10m left" / nil while macOS is still estimating.
    static func estimate(_ snapshot: BatterySnapshot, bundle: Bundle = .main, locale: Locale = .current) -> String? {
        if snapshot.isCharging, let seconds = snapshot.timeToFull {
            return String(localized: "battery.estimate.toFull", defaultValue: "\(formatTime(seconds, locale: locale)) to full", bundle: bundle)
        }
        if !snapshot.isPluggedIn, let seconds = snapshot.timeToEmpty {
            return String(localized: "battery.estimate.left", defaultValue: "\(formatTime(seconds, locale: locale)) left", bundle: bundle)
        }
        return nil
    }

    static func percentText(_ snapshot: BatterySnapshot, bundle: Bundle = .main) -> String {
        String(localized: "percent", defaultValue: "\(snapshot.percentage)%", bundle: bundle)
    }

    /// The popup for an alert: title, detail, symbol and how long it stays.
    static func event(for alert: BatteryAlert, snapshot: BatterySnapshot, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        let percent = percentText(snapshot, bundle: bundle)
        let estimate = estimate(snapshot, bundle: bundle)
        switch alert {
        case .pluggedIn:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "battery.event.pluggedIn", defaultValue: "Charging", bundle: bundle),
                              detail: [percent, estimate].compactMap { $0 }.joined(separator: " — "),
                              symbolName: "bolt.fill", duration: 2.5)
        case .unplugged:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "battery.event.unplugged", defaultValue: "On battery", bundle: bundle),
                              detail: [percent, estimate].compactMap { $0 }.joined(separator: " — "),
                              symbolName: "battery.75percent", duration: 2.5)
        case .low:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "battery.event.low", defaultValue: "Battery low", bundle: bundle),
                              detail: [percent, estimate].compactMap { $0 }.joined(separator: " — "),
                              symbolName: "battery.25percent", duration: 4)
        case .critical:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "battery.event.critical", defaultValue: "Battery critical", bundle: bundle),
                              detail: String(localized: "battery.event.critical.detail", defaultValue: "\(percent) — plug in soon", bundle: bundle),
                              symbolName: "exclamationmark.triangle.fill", duration: 4)
        case .full:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "battery.event.full", defaultValue: "Fully charged", bundle: bundle),
                              detail: nil, symbolName: "battery.100percent.bolt", duration: 2.5)
        case .lowPowerModeOn:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "battery.event.lowPowerOn", defaultValue: "Low Power Mode on", bundle: bundle),
                              detail: nil, symbolName: "leaf.fill", duration: 2)
        case .lowPowerModeOff:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "battery.event.lowPowerOff", defaultValue: "Low Power Mode off", bundle: bundle),
                              detail: nil, symbolName: "leaf", duration: 2)
        }
    }

    // MARK: Explanations

    static func gaugeExplanation(_ snapshot: BatterySnapshot, thresholds: BatteryThresholds, bundle: Bundle = .main) -> String {
        let low = Int((thresholds.low * 100).rounded())
        let critical = Int((thresholds.critical * 100).rounded())
        return String(localized: "battery.explain.gauge",
                      defaultValue: "\(percentText(snapshot, bundle: bundle)) charged. The gauge turns orange at \(low)% and red at \(critical)%; both are set in Settings.",
                      bundle: bundle)
    }

    static func statusExplanation(_ snapshot: BatterySnapshot, bundle: Bundle = .main) -> String {
        if snapshot.isCharging {
            return String(localized: "battery.explain.charging", defaultValue: "Taking charge from the adapter. The estimate is macOS's own and changes with the load.", bundle: bundle)
        }
        if snapshot.isPluggedIn {
            return String(localized: "battery.explain.plugged", defaultValue: "On power. macOS holds the charge here to protect the battery.", bundle: bundle)
        }
        return String(localized: "battery.explain.onBattery", defaultValue: "Running on the battery. The time left is macOS's estimate from the current drain.", bundle: bundle)
    }

    static func lowPowerExplanation(_ snapshot: BatterySnapshot, bundle: Bundle = .main) -> String {
        snapshot.isLowPowerMode
            ? String(localized: "battery.explain.lowPowerOn", defaultValue: "Low Power Mode is on: slower processor, dimmer screen, longer runtime.", bundle: bundle)
            : String(localized: "battery.explain.lowPowerOff", defaultValue: "Low Power Mode is off. Turn it on in System Settings → Battery when you need the hours.", bundle: bundle)
    }
}
