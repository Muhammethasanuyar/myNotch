import Foundation
import Observation

/// Every preference the app persists, by its `UserDefaults` key. The raw values are the keys the
/// earlier phases already used with `defaults write`, so nothing the user set by hand is lost.
nonisolated enum SettingsKey: String, CaseIterable, Sendable {
    // Engine
    case hoverDelay
    case closeDelay
    case hapticsEnabled
    case disabledModules
    case displaySelection
    // Media
    case lyricsEnabled
    case lyricsLeadSeconds
    case lyricsShifts
    case spotifyClientID
    // Claude usage
    case usageWarningThreshold
    case usageCriticalThreshold
    case usagePollInterval
    case usageAlertsEnabled
    case ccusagePath
    case claudeConfigDir
    // App
    case onboardingCompleted
}

/// Pure limits for the values the settings window can set: a hand-edited default can never put the
/// engine in a state the UI would not allow.
nonisolated enum SettingsRules {
    static let hoverDelayRange: ClosedRange<TimeInterval> = 0.05...1.0
    /// The user asked for the grace period to stay under a second.
    static let closeDelayRange: ClosedRange<TimeInterval> = 0.1...1.0
    static let lyricsLeadRange: ClosedRange<TimeInterval> = -1.0...1.0
    static let warningRange: ClosedRange<Double> = 0.5...0.95
    static let criticalRange: ClosedRange<Double> = 0.55...1.0
    /// Smallest gap kept between the two thresholds, so both alerts can fire.
    static let thresholdGap = 0.05
    /// Poll intervals the picker offers, in seconds; the first is the endpoint's floor.
    static let pollIntervalChoices: [TimeInterval] = [300, 600, 900, 1800]

    static func hoverDelay(_ value: TimeInterval) -> TimeInterval { clamp(value, to: hoverDelayRange) }
    static func closeDelay(_ value: TimeInterval) -> TimeInterval { clamp(value, to: closeDelayRange) }
    static func lyricsLead(_ value: TimeInterval) -> TimeInterval { clamp(value, to: lyricsLeadRange) }

    /// Both thresholds inside their ranges and `critical` at least `thresholdGap` above `warning`.
    static func thresholds(warning: Double, critical: Double) -> (warning: Double, critical: Double) {
        let warning = clamp(warning, to: warningRange)
        let critical = max(clamp(critical, to: criticalRange), min(warning + thresholdGap, criticalRange.upperBound))
        return (warning, critical)
    }

    /// The offered interval closest to `value`, never below the floor.
    static func pollInterval(_ value: TimeInterval) -> TimeInterval {
        pollIntervalChoices.min { abs($0 - value) < abs($1 - value) } ?? pollIntervalChoices[0]
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The app's preferences, read once from `UserDefaults` and written back on every change.
///
/// Nothing here knows about the engine or the modules: `SettingsApplier` listens to `onChange`
/// and pushes the new value where it belongs, so this store stays testable with a throwaway suite.
@MainActor
@Observable
final class SettingsStore {
    /// Fired after a value has been persisted, with the key that changed.
    @ObservationIgnored var onChange: ((SettingsKey) -> Void)?

    // MARK: Engine

    /// Clamped on write: `@Observable` recurses if a `didSet` assigns to its own property, so the
    /// bounded values keep explicit accessors over ignored storage.
    var hoverDelay: TimeInterval {
        get { access(keyPath: \.hoverDelay); return storedHoverDelay }
        set { withMutation(keyPath: \.hoverDelay) { storedHoverDelay = SettingsRules.hoverDelay(newValue) }; persist(storedHoverDelay, .hoverDelay) }
    }
    var closeDelay: TimeInterval {
        get { access(keyPath: \.closeDelay); return storedCloseDelay }
        set { withMutation(keyPath: \.closeDelay) { storedCloseDelay = SettingsRules.closeDelay(newValue) }; persist(storedCloseDelay, .closeDelay) }
    }
    var hapticsEnabled: Bool { didSet { persist(hapticsEnabled, .hapticsEnabled) } }
    /// Modules are on unless listed here, so a module added later starts enabled.
    private(set) var disabledModuleIDs: Set<String>
    var displaySelection: ScreenPreference { didSet { persist(displaySelection.storedValue, .displaySelection) } }

    // MARK: Media

    var lyricsEnabled: Bool { didSet { persist(lyricsEnabled, .lyricsEnabled) } }
    var lyricsLeadSeconds: TimeInterval {
        get { access(keyPath: \.lyricsLeadSeconds); return storedLyricsLead }
        set { withMutation(keyPath: \.lyricsLeadSeconds) { storedLyricsLead = SettingsRules.lyricsLead(newValue) }; persist(storedLyricsLead, .lyricsLeadSeconds) }
    }
    /// Empty means "not configured"; the key is removed rather than storing an empty string.
    var spotifyClientID: String { didSet { persist(trimmed(spotifyClientID), .spotifyClientID) } }

    // MARK: Claude usage

    /// Moving either threshold keeps `critical` above `warning`; both are persisted, one key is announced.
    var usageWarningThreshold: Double {
        get { access(keyPath: \.usageWarningThreshold); return storedWarning }
        set { setThresholds(warning: newValue, critical: storedCritical, changed: .usageWarningThreshold) }
    }
    var usageCriticalThreshold: Double {
        get { access(keyPath: \.usageCriticalThreshold); return storedCritical }
        set { setThresholds(warning: storedWarning, critical: newValue, changed: .usageCriticalThreshold) }
    }
    var usagePollInterval: TimeInterval {
        get { access(keyPath: \.usagePollInterval); return storedPollInterval }
        set { withMutation(keyPath: \.usagePollInterval) { storedPollInterval = SettingsRules.pollInterval(newValue) }; persist(storedPollInterval, .usagePollInterval) }
    }
    var usageAlertsEnabled: Bool { didSet { persist(usageAlertsEnabled, .usageAlertsEnabled) } }
    var ccusagePath: String { didSet { persist(trimmed(ccusagePath), .ccusagePath) } }
    var claudeConfigDir: String { didSet { persist(trimmed(claudeConfigDir), .claudeConfigDir) } }

    // MARK: App

    var onboardingCompleted: Bool { didSet { persist(onboardingCompleted, .onboardingCompleted) } }

    static let defaultHoverDelay: TimeInterval = 0.15
    static let defaultCloseDelay: TimeInterval = 0.8
    static let defaultLyricsLead: TimeInterval = 0.15
    static let defaultWarningThreshold = 0.80
    static let defaultCriticalThreshold = 0.95

    private let defaults: UserDefaults
    @ObservationIgnored private var storedHoverDelay: TimeInterval
    @ObservationIgnored private var storedCloseDelay: TimeInterval
    @ObservationIgnored private var storedLyricsLead: TimeInterval
    @ObservationIgnored private var storedWarning: Double
    @ObservationIgnored private var storedCritical: Double
    @ObservationIgnored private var storedPollInterval: TimeInterval

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedHoverDelay = SettingsRules.hoverDelay(defaults.object(forKey: SettingsKey.hoverDelay.rawValue) as? Double ?? Self.defaultHoverDelay)
        storedCloseDelay = SettingsRules.closeDelay(defaults.object(forKey: SettingsKey.closeDelay.rawValue) as? Double ?? Self.defaultCloseDelay)
        hapticsEnabled = defaults.object(forKey: SettingsKey.hapticsEnabled.rawValue) as? Bool ?? true
        disabledModuleIDs = Set(defaults.stringArray(forKey: SettingsKey.disabledModules.rawValue) ?? [])
        displaySelection = ScreenPreference(storedValue: defaults.string(forKey: SettingsKey.displaySelection.rawValue))
        lyricsEnabled = defaults.object(forKey: SettingsKey.lyricsEnabled.rawValue) as? Bool ?? true
        storedLyricsLead = SettingsRules.lyricsLead(defaults.object(forKey: SettingsKey.lyricsLeadSeconds.rawValue) as? Double ?? Self.defaultLyricsLead)
        spotifyClientID = defaults.string(forKey: SettingsKey.spotifyClientID.rawValue) ?? ""
        let thresholds = SettingsRules.thresholds(
            warning: defaults.object(forKey: SettingsKey.usageWarningThreshold.rawValue) as? Double ?? Self.defaultWarningThreshold,
            critical: defaults.object(forKey: SettingsKey.usageCriticalThreshold.rawValue) as? Double ?? Self.defaultCriticalThreshold
        )
        storedWarning = thresholds.warning
        storedCritical = thresholds.critical
        storedPollInterval = SettingsRules.pollInterval(defaults.object(forKey: SettingsKey.usagePollInterval.rawValue) as? Double ?? SettingsRules.pollIntervalChoices[0])
        usageAlertsEnabled = defaults.object(forKey: SettingsKey.usageAlertsEnabled.rawValue) as? Bool ?? true
        ccusagePath = defaults.string(forKey: SettingsKey.ccusagePath.rawValue) ?? ""
        claudeConfigDir = defaults.string(forKey: SettingsKey.claudeConfigDir.rawValue) ?? ""
        onboardingCompleted = defaults.bool(forKey: SettingsKey.onboardingCompleted.rawValue)
    }

    // MARK: Modules

    func isModuleEnabled(_ moduleID: String) -> Bool {
        !disabledModuleIDs.contains(moduleID)
    }

    func setModule(_ moduleID: String, enabled: Bool) {
        let changed = enabled ? disabledModuleIDs.remove(moduleID) != nil : disabledModuleIDs.insert(moduleID).inserted
        guard changed else { return }
        persist(disabledModuleIDs.sorted(), .disabledModules)
    }

    // MARK: Actions

    /// Forgets every per-song lyrics offset; the service drops its copy through `onChange`.
    func resetLyricsShifts() {
        persist(nil, .lyricsShifts)
    }

    /// The engine knobs back to how the app ships.
    func resetEngineDefaults() {
        hoverDelay = Self.defaultHoverDelay
        closeDelay = Self.defaultCloseDelay
        hapticsEnabled = true
        displaySelection = .automatic
    }

    func resetThresholds() {
        usageWarningThreshold = Self.defaultWarningThreshold
        usageCriticalThreshold = Self.defaultCriticalThreshold
    }

    // MARK: Persistence

    private func persist(_ value: Any?, _ key: SettingsKey) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
        onChange?(key)
    }

    /// Whitespace-only text counts as unset.
    private func trimmed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func setThresholds(warning: Double, critical: Double, changed key: SettingsKey) {
        let fixed = SettingsRules.thresholds(warning: warning, critical: critical)
        withMutation(keyPath: \.usageWarningThreshold) {
            withMutation(keyPath: \.usageCriticalThreshold) {
                storedWarning = fixed.warning
                storedCritical = fixed.critical
            }
        }
        defaults.set(storedWarning, forKey: SettingsKey.usageWarningThreshold.rawValue)
        defaults.set(storedCritical, forKey: SettingsKey.usageCriticalThreshold.rawValue)
        onChange?(key)
    }
}
