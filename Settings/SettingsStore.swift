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
    case visualizerEnabled
    case genericPlayerEnabled
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
    // Battery
    case batteryLowThreshold
    case batteryCriticalThreshold
    case batteryAlertsEnabled
    // Pomodoro
    case pomodoroWorkMinutes
    case pomodoroBreakMinutes
    case pomodoroLongBreakMinutes
    case pomodoroLongBreakEvery
    case pomodoroAutoStart
    case pomodoroSoundEnabled
    // Calendar
    case calendarLeadMinutes
    case calendarSelectedIDs
    case calendarAlertsEnabled
    // Shelf
    case shelfKeepInterval
    // App
    case onboardingCompleted
    case updateChecksEnabled
    /// Module ids whose shipped default has been written into `disabledModules` once.
    case moduleDefaultsApplied
}

/// Modules that ship switched off because turning them on has a cost the user should choose:
/// the downloads watcher raises the Downloads-folder permission prompt, the CI module runs an
/// external command line tool. Everything else starts on.
nonisolated enum ModuleDefaults {
    static let disabledByDefault: Set<String> = ["downloads", "ci"]

    /// The ids to add to the disabled set now: shipped-off modules whose default was never applied.
    /// Idempotent — a user who turned one on stays on, because its id is already marked applied.
    static func pendingDisables(applied: Set<String>) -> Set<String> {
        disabledByDefault.subtracting(applied)
    }
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
    static let batteryLowRange: ClosedRange<Double> = 0.10...0.35
    static let batteryCriticalRange: ClosedRange<Double> = 0.05...0.25
    /// Smallest gap kept between the battery's low and critical levels.
    static let batteryThresholdGap = 0.05
    static let pomodoroWorkRange = 5...90
    static let pomodoroBreakRange = 1...30
    static let pomodoroLongBreakRange = 5...60
    static let pomodoroLongBreakEveryRange = 2...8
    static let calendarLeadRange = 1...60

    static func hoverDelay(_ value: TimeInterval) -> TimeInterval { clamp(value, to: hoverDelayRange) }
    static func closeDelay(_ value: TimeInterval) -> TimeInterval { clamp(value, to: closeDelayRange) }
    static func lyricsLead(_ value: TimeInterval) -> TimeInterval { clamp(value, to: lyricsLeadRange) }

    /// Both thresholds inside their ranges and `critical` at least `thresholdGap` above `warning`.
    static func thresholds(warning: Double, critical: Double) -> (warning: Double, critical: Double) {
        let warning = clamp(warning, to: warningRange)
        let critical = max(clamp(critical, to: criticalRange), min(warning + thresholdGap, criticalRange.upperBound))
        return (warning, critical)
    }

    /// Both battery levels inside their ranges and `critical` at least `batteryThresholdGap` below `low`.
    static func batteryThresholds(low: Double, critical: Double) -> (low: Double, critical: Double) {
        let low = clamp(low, to: batteryLowRange)
        let critical = min(clamp(critical, to: batteryCriticalRange), max(low - batteryThresholdGap, batteryCriticalRange.lowerBound))
        return (low, critical)
    }

    static func calendarLead(_ minutes: Int) -> Int { clamp(minutes, to: calendarLeadRange) }
    /// One of the shelf's offered retention periods; zero is "until removed".
    static func shelfKeepInterval(_ seconds: TimeInterval) -> TimeInterval { ShelfRules.snappedKeepInterval(seconds) }

    /// Every pomodoro length inside its range.
    static func pomodoroConfig(work: Int, breakMinutes: Int, longBreak: Int, every: Int) -> PomodoroConfig {
        PomodoroConfig(
            workMinutes: clamp(work, to: pomodoroWorkRange),
            breakMinutes: clamp(breakMinutes, to: pomodoroBreakRange),
            longBreakMinutes: clamp(longBreak, to: pomodoroLongBreakRange),
            longBreakEvery: clamp(every, to: pomodoroLongBreakEveryRange)
        )
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

    /// Off until asked for: the tap needs a system-audio recording permission.
    var visualizerEnabled: Bool { didSet { persist(visualizerEnabled, .visualizerEnabled) } }
    /// Off until asked for: runs a helper that reads a private framework through perl.
    var genericPlayerEnabled: Bool { didSet { persist(genericPlayerEnabled, .genericPlayerEnabled) } }
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

    // MARK: Battery

    var batteryLowThreshold: Double {
        get { access(keyPath: \.batteryLowThreshold); return storedBatteryLow }
        set { setBatteryThresholds(low: newValue, critical: storedBatteryCritical, changed: .batteryLowThreshold) }
    }
    var batteryCriticalThreshold: Double {
        get { access(keyPath: \.batteryCriticalThreshold); return storedBatteryCritical }
        set { setBatteryThresholds(low: storedBatteryLow, critical: newValue, changed: .batteryCriticalThreshold) }
    }
    var batteryAlertsEnabled: Bool { didSet { persist(batteryAlertsEnabled, .batteryAlertsEnabled) } }

    // MARK: Pomodoro

    var pomodoroWorkMinutes: Int {
        get { access(keyPath: \.pomodoroWorkMinutes); return storedPomodoro.workMinutes }
        set { setPomodoro(work: newValue, changed: .pomodoroWorkMinutes) }
    }
    var pomodoroBreakMinutes: Int {
        get { access(keyPath: \.pomodoroBreakMinutes); return storedPomodoro.breakMinutes }
        set { setPomodoro(breakMinutes: newValue, changed: .pomodoroBreakMinutes) }
    }
    var pomodoroLongBreakMinutes: Int {
        get { access(keyPath: \.pomodoroLongBreakMinutes); return storedPomodoro.longBreakMinutes }
        set { setPomodoro(longBreak: newValue, changed: .pomodoroLongBreakMinutes) }
    }
    var pomodoroLongBreakEvery: Int {
        get { access(keyPath: \.pomodoroLongBreakEvery); return storedPomodoro.longBreakEvery }
        set { setPomodoro(every: newValue, changed: .pomodoroLongBreakEvery) }
    }
    var pomodoroAutoStart: Bool { didSet { persist(pomodoroAutoStart, .pomodoroAutoStart) } }
    var pomodoroSoundEnabled: Bool { didSet { persist(pomodoroSoundEnabled, .pomodoroSoundEnabled) } }

    /// The timer's configuration as the store holds it.
    var pomodoroConfig: PomodoroConfig {
        var config = storedPomodoro
        config.autoStart = pomodoroAutoStart
        config.soundEnabled = pomodoroSoundEnabled
        return config
    }

    // MARK: Calendar

    var calendarLeadMinutes: Int {
        get { access(keyPath: \.calendarLeadMinutes); return storedCalendarLead }
        set { withMutation(keyPath: \.calendarLeadMinutes) { storedCalendarLead = SettingsRules.calendarLead(newValue) }; persist(storedCalendarLead, .calendarLeadMinutes) }
    }
    /// Calendar identifiers that count; empty means every calendar.
    var calendarSelectedIDs: [String] { didSet { persist(calendarSelectedIDs.isEmpty ? nil : calendarSelectedIDs, .calendarSelectedIDs) } }
    var calendarAlertsEnabled: Bool { didSet { persist(calendarAlertsEnabled, .calendarAlertsEnabled) } }

    // MARK: Shelf

    /// How long the shelf keeps a copy, in seconds; `0` keeps it until removed by hand.
    var shelfKeepInterval: TimeInterval {
        get { access(keyPath: \.shelfKeepInterval); return storedShelfKeep }
        set { withMutation(keyPath: \.shelfKeepInterval) { storedShelfKeep = SettingsRules.shelfKeepInterval(newValue) }; persist(storedShelfKeep, .shelfKeepInterval) }
    }

    // MARK: App

    var onboardingCompleted: Bool { didSet { persist(onboardingCompleted, .onboardingCompleted) } }
    /// Sparkle's daily appcast check; the only thing the app does on the network unasked.
    var updateChecksEnabled: Bool { didSet { persist(updateChecksEnabled, .updateChecksEnabled) } }

    static let defaultHoverDelay: TimeInterval = 0.15
    static let defaultCloseDelay: TimeInterval = 0.8
    static let defaultLyricsLead: TimeInterval = 0.15
    static let defaultWarningThreshold = 0.80
    static let defaultCriticalThreshold = 0.95
    static let defaultBatteryLow = 0.20
    static let defaultBatteryCritical = 0.10
    static let defaultCalendarLead = 15

    private let defaults: UserDefaults
    @ObservationIgnored private var storedHoverDelay: TimeInterval
    @ObservationIgnored private var storedCloseDelay: TimeInterval
    @ObservationIgnored private var storedLyricsLead: TimeInterval
    @ObservationIgnored private var storedWarning: Double
    @ObservationIgnored private var storedCritical: Double
    @ObservationIgnored private var storedPollInterval: TimeInterval
    @ObservationIgnored private var storedBatteryLow: Double
    @ObservationIgnored private var storedBatteryCritical: Double
    /// Lengths only; the two switches are ordinary stored properties.
    @ObservationIgnored private var storedPomodoro: PomodoroConfig
    @ObservationIgnored private var storedCalendarLead: Int
    @ObservationIgnored private var storedShelfKeep: TimeInterval

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedHoverDelay = SettingsRules.hoverDelay(defaults.object(forKey: SettingsKey.hoverDelay.rawValue) as? Double ?? Self.defaultHoverDelay)
        storedCloseDelay = SettingsRules.closeDelay(defaults.object(forKey: SettingsKey.closeDelay.rawValue) as? Double ?? Self.defaultCloseDelay)
        hapticsEnabled = defaults.object(forKey: SettingsKey.hapticsEnabled.rawValue) as? Bool ?? true
        var disabled = Set(defaults.stringArray(forKey: SettingsKey.disabledModules.rawValue) ?? [])
        var applied = Set(defaults.stringArray(forKey: SettingsKey.moduleDefaultsApplied.rawValue) ?? [])
        let pending = ModuleDefaults.pendingDisables(applied: applied)
        if !pending.isEmpty {
            disabled.formUnion(pending)
            applied.formUnion(pending)
            defaults.set(disabled.sorted(), forKey: SettingsKey.disabledModules.rawValue)
            defaults.set(applied.sorted(), forKey: SettingsKey.moduleDefaultsApplied.rawValue)
        }
        disabledModuleIDs = disabled
        displaySelection = ScreenPreference(storedValue: defaults.string(forKey: SettingsKey.displaySelection.rawValue))
        visualizerEnabled = defaults.object(forKey: SettingsKey.visualizerEnabled.rawValue) as? Bool ?? false
        genericPlayerEnabled = defaults.object(forKey: SettingsKey.genericPlayerEnabled.rawValue) as? Bool ?? false
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
        let battery = SettingsRules.batteryThresholds(
            low: defaults.object(forKey: SettingsKey.batteryLowThreshold.rawValue) as? Double ?? Self.defaultBatteryLow,
            critical: defaults.object(forKey: SettingsKey.batteryCriticalThreshold.rawValue) as? Double ?? Self.defaultBatteryCritical
        )
        storedBatteryLow = battery.low
        storedBatteryCritical = battery.critical
        batteryAlertsEnabled = defaults.object(forKey: SettingsKey.batteryAlertsEnabled.rawValue) as? Bool ?? true
        let shipped = PomodoroConfig()
        storedPomodoro = SettingsRules.pomodoroConfig(
            work: defaults.object(forKey: SettingsKey.pomodoroWorkMinutes.rawValue) as? Int ?? shipped.workMinutes,
            breakMinutes: defaults.object(forKey: SettingsKey.pomodoroBreakMinutes.rawValue) as? Int ?? shipped.breakMinutes,
            longBreak: defaults.object(forKey: SettingsKey.pomodoroLongBreakMinutes.rawValue) as? Int ?? shipped.longBreakMinutes,
            every: defaults.object(forKey: SettingsKey.pomodoroLongBreakEvery.rawValue) as? Int ?? shipped.longBreakEvery
        )
        pomodoroAutoStart = defaults.object(forKey: SettingsKey.pomodoroAutoStart.rawValue) as? Bool ?? shipped.autoStart
        pomodoroSoundEnabled = defaults.object(forKey: SettingsKey.pomodoroSoundEnabled.rawValue) as? Bool ?? shipped.soundEnabled
        storedCalendarLead = SettingsRules.calendarLead(defaults.object(forKey: SettingsKey.calendarLeadMinutes.rawValue) as? Int ?? Self.defaultCalendarLead)
        calendarSelectedIDs = defaults.stringArray(forKey: SettingsKey.calendarSelectedIDs.rawValue) ?? []
        calendarAlertsEnabled = defaults.object(forKey: SettingsKey.calendarAlertsEnabled.rawValue) as? Bool ?? true
        storedShelfKeep = SettingsRules.shelfKeepInterval(defaults.object(forKey: SettingsKey.shelfKeepInterval.rawValue) as? Double ?? ShelfRules.defaultKeepInterval)
        onboardingCompleted = defaults.bool(forKey: SettingsKey.onboardingCompleted.rawValue)
        updateChecksEnabled = defaults.object(forKey: SettingsKey.updateChecksEnabled.rawValue) as? Bool ?? true
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

    func resetBatteryThresholds() {
        batteryLowThreshold = Self.defaultBatteryLow
        batteryCriticalThreshold = Self.defaultBatteryCritical
    }

    /// The timer's lengths and switches back to how the app ships.
    func resetPomodoro() {
        let shipped = PomodoroConfig()
        setPomodoro(work: shipped.workMinutes, breakMinutes: shipped.breakMinutes, longBreak: shipped.longBreakMinutes, every: shipped.longBreakEvery, changed: .pomodoroWorkMinutes)
        pomodoroAutoStart = shipped.autoStart
        pomodoroSoundEnabled = shipped.soundEnabled
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

    private func setPomodoro(work: Int? = nil, breakMinutes: Int? = nil, longBreak: Int? = nil, every: Int? = nil, changed key: SettingsKey) {
        let fixed = SettingsRules.pomodoroConfig(
            work: work ?? storedPomodoro.workMinutes,
            breakMinutes: breakMinutes ?? storedPomodoro.breakMinutes,
            longBreak: longBreak ?? storedPomodoro.longBreakMinutes,
            every: every ?? storedPomodoro.longBreakEvery
        )
        withMutation(keyPath: \.pomodoroWorkMinutes) {
            withMutation(keyPath: \.pomodoroBreakMinutes) {
                withMutation(keyPath: \.pomodoroLongBreakMinutes) {
                    withMutation(keyPath: \.pomodoroLongBreakEvery) {
                        storedPomodoro = fixed
                    }
                }
            }
        }
        defaults.set(fixed.workMinutes, forKey: SettingsKey.pomodoroWorkMinutes.rawValue)
        defaults.set(fixed.breakMinutes, forKey: SettingsKey.pomodoroBreakMinutes.rawValue)
        defaults.set(fixed.longBreakMinutes, forKey: SettingsKey.pomodoroLongBreakMinutes.rawValue)
        defaults.set(fixed.longBreakEvery, forKey: SettingsKey.pomodoroLongBreakEvery.rawValue)
        onChange?(key)
    }

    private func setBatteryThresholds(low: Double, critical: Double, changed key: SettingsKey) {
        let fixed = SettingsRules.batteryThresholds(low: low, critical: critical)
        withMutation(keyPath: \.batteryLowThreshold) {
            withMutation(keyPath: \.batteryCriticalThreshold) {
                storedBatteryLow = fixed.low
                storedBatteryCritical = fixed.critical
            }
        }
        defaults.set(storedBatteryLow, forKey: SettingsKey.batteryLowThreshold.rawValue)
        defaults.set(storedBatteryCritical, forKey: SettingsKey.batteryCriticalThreshold.rawValue)
        onChange?(key)
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
