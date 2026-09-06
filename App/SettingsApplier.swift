import Foundation

/// Pushes a changed setting to the object that acts on it. The store knows nothing about the
/// engine or the modules; this is the one place that knows both.
@MainActor
struct SettingsApplier {
    let store: SettingsStore
    let model: NotchViewModel
    let manager: ModuleManager
    let notch: NotchWindowController
    var updater: UpdaterManager? = nil

    /// Launch: the values the objects do not read for themselves. Module on/off flags are set
    /// before registration, and the path keys would only redo work `start()` has just done.
    static let appliedAtLaunch: [SettingsKey] = [
        .hoverDelay, .closeDelay, .hapticsEnabled, .displaySelection, .visualizerEnabled, .genericPlayerEnabled,
        .usageWarningThreshold, .usagePollInterval, .usageAlertsEnabled,
        .batteryLowThreshold, .batteryAlertsEnabled, .pomodoroWorkMinutes,
        .calendarLeadMinutes, .calendarSelectedIDs, .calendarAlertsEnabled, .shelfKeepInterval,
        .volumePopupsEnabled, .volumeHUDReplacement, .updateChecksEnabled
    ]

    func applyAll() {
        for key in Self.appliedAtLaunch {
            apply(key)
        }
    }

    func apply(_ key: SettingsKey) {
        switch key {
        case .hoverDelay:
            model.hoverDelay = store.hoverDelay
        case .closeDelay:
            model.closeDelay = store.closeDelay
        case .hapticsEnabled:
            model.hapticsEnabled = store.hapticsEnabled
        case .disabledModules:
            for module in manager.modules {
                manager.setEnabled(store.isModuleEnabled(module.id), for: module.id)
            }
        case .displaySelection:
            notch.screenPreference = store.displaySelection
        case .visualizerEnabled:
            media?.controller.setVisualizer(enabled: store.visualizerEnabled)
        case .genericPlayerEnabled:
            media?.controller.setGenericPlayer(enabled: store.genericPlayerEnabled)
        case .lyricsEnabled:
            // The service reads the flag on every load; only the lyrics on screen need a nudge.
            media?.controller.lyricsSettingChanged()
        case .lyricsLeadSeconds:
            break // Read live by the lyrics view.
        case .lyricsShifts:
            media?.controller.lyrics.clearShifts()
        case .spotifyClientID:
            media?.controller.spotifyLibrary?.refreshConfiguration()
        case .usageWarningThreshold, .usageCriticalThreshold:
            claude?.service.thresholds = UsageThresholds(warning: store.usageWarningThreshold, critical: store.usageCriticalThreshold)
        case .usagePollInterval:
            claude?.service.pollInterval = store.usagePollInterval
        case .usageAlertsEnabled:
            claude?.alertsEnabled = store.usageAlertsEnabled
        case .ccusagePath:
            claude?.service.relocateCCUsage()
        case .claudeConfigDir:
            // Credentials, logs and ccusage all hang off the directory: start over.
            guard let claude, claude.isEnabled else { return }
            claude.service.stop()
            claude.service.start()
        case .batteryLowThreshold, .batteryCriticalThreshold:
            battery?.service.thresholds = BatteryThresholds(low: store.batteryLowThreshold, critical: store.batteryCriticalThreshold)
        case .batteryAlertsEnabled:
            battery?.alertsEnabled = store.batteryAlertsEnabled
        case .shelfKeepInterval:
            shelf?.store.keepInterval = store.shelfKeepInterval
        case .volumePopupsEnabled:
            volume?.service.popupsEnabled = store.volumePopupsEnabled
        case .volumeHUDReplacement:
            volume?.service.hudReplacement = store.volumeHUDReplacement
        case .updateChecksEnabled:
            updater?.automaticallyChecksForUpdates = store.updateChecksEnabled
        case .moduleDefaultsApplied:
            // Bookkeeping the store does for itself at launch; nothing to push.
            break
        case .pomodoroWorkMinutes, .pomodoroBreakMinutes, .pomodoroLongBreakMinutes, .pomodoroLongBreakEvery, .pomodoroAutoStart, .pomodoroSoundEnabled:
            pomodoro?.timer.config = store.pomodoroConfig
        case .calendarLeadMinutes:
            calendar?.service.leadMinutes = store.calendarLeadMinutes
        case .calendarSelectedIDs:
            calendar?.service.selectedCalendarIDs = Set(store.calendarSelectedIDs)
        case .calendarAlertsEnabled:
            calendar?.alertsEnabled = store.calendarAlertsEnabled
        case .onboardingCompleted:
            break
        }
    }

    private var media: MediaModule? {
        manager.module(id: "media") as? MediaModule
    }

    private var claude: ClaudeUsageModule? {
        manager.module(id: "claude") as? ClaudeUsageModule
    }

    private var battery: BatteryModule? {
        manager.module(id: "battery") as? BatteryModule
    }

    private var pomodoro: PomodoroModule? {
        manager.module(id: "pomodoro") as? PomodoroModule
    }

    private var calendar: CalendarModule? {
        manager.module(id: "calendar") as? CalendarModule
    }

    private var shelf: ShelfModule? {
        manager.module(id: "shelf") as? ShelfModule
    }

    private var volume: VolumeModule? {
        manager.module(id: "volume") as? VolumeModule
    }
}
