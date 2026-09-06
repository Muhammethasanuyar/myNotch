import Foundation

/// What the power source reports, reduced to what the notch shows.
nonisolated struct BatterySnapshot: Equatable, Sendable {
    var isCharging: Bool
    /// On mains power, whether or not the battery is still taking charge.
    var isPluggedIn: Bool
    /// 0…100.
    var percentage: Int
    /// Seconds until full while charging; `nil` while macOS is still estimating or not charging.
    var timeToFull: TimeInterval?
    /// Seconds until empty on battery; `nil` while estimating or on mains.
    var timeToEmpty: TimeInterval?
    var isLowPowerMode: Bool

    var isFull: Bool { isPluggedIn && percentage >= 100 }
}

/// Fractions of a full charge at which the module warns, ascending in urgency.
nonisolated struct BatteryThresholds: Equatable, Sendable {
    var low: Double = 0.20
    var critical: Double = 0.10
}

/// What the module wants to announce; the module turns these into localized events.
nonisolated enum BatteryAlert: Equatable, Sendable {
    case pluggedIn
    case unplugged
    case low
    case critical
    case full
    case lowPowerModeOn
    case lowPowerModeOff
}

/// Remembers which one-shot alerts have fired so a level hovering around a threshold does not
/// announce it again and again. Re-armed when charging starts or the level climbs well clear.
nonisolated struct BatteryAlertMemory: Equatable, Sendable {
    var announcedLow = false
    var announcedCritical = false
    var announcedFull = false
}
