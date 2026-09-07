import Foundation
import Observation

/// The sidebar entries. Raw values double as the `-openSettings <tab>` launch argument.
nonisolated enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case modules
    case media
    case claude
    case calendar
    case battery
    case pomodoro
    case shelf
    case downloads
    case ci
    case sound
    case setup
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: L("settings.tab.general", "General")
        case .modules: L("settings.tab.modules", "Modules")
        case .media: L("settings.tab.media", "Media")
        case .claude: L("settings.tab.claude", "Claude")
        case .calendar: L("settings.tab.calendar", "Calendar")
        case .battery: L("settings.tab.battery", "Battery")
        case .pomodoro: L("settings.tab.pomodoro", "Pomodoro")
        case .shelf: L("settings.tab.shelf", "Shelf")
        case .downloads: L("settings.tab.downloads", "Downloads")
        case .ci: L("settings.tab.ci", "Builds")
        case .sound: L("settings.tab.sound", "Sound")
        case .setup: L("settings.tab.setup", "Setup")
        case .about: L("settings.tab.about", "About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .modules: "square.grid.2x2"
        case .media: "music.note"
        case .claude: "asterisk"
        case .calendar: "calendar"
        case .battery: "battery.100percent.bolt"
        case .pomodoro: "timer"
        case .shelf: "tray.full.fill"
        case .downloads: "arrow.down.circle"
        case .ci: "hammer"
        case .sound: "speaker.wave.2"
        case .setup: "checklist"
        case .about: "info.circle"
        }
    }
}

/// Which pane is showing; owned by the window controller so `show(tab:)` can steer it.
@Observable
final class SettingsNavigation {
    var selectedTab: SettingsTab? = .general
}

/// Everything the panes read and act on. Modules are reached through the manager, so one that is
/// switched off still appears in the list and can be switched back on.
struct SettingsContext {
    let store: SettingsStore
    let manager: ModuleManager
    let launchAtLogin: LaunchAtLogin
    let openDebugPreview: @MainActor () -> Void
    let checkForUpdates: @MainActor () -> Void

    var media: MediaModule? {
        manager.module(id: "media") as? MediaModule
    }

    var claude: ClaudeUsageModule? {
        manager.module(id: "claude") as? ClaudeUsageModule
    }

    var battery: BatteryModule? {
        manager.module(id: "battery") as? BatteryModule
    }

    var pomodoro: PomodoroModule? {
        manager.module(id: "pomodoro") as? PomodoroModule
    }

    var calendar: CalendarModule? {
        manager.module(id: "calendar") as? CalendarModule
    }

    var shelf: ShelfModule? {
        manager.module(id: "shelf") as? ShelfModule
    }

    var volume: VolumeModule? {
        manager.module(id: "volume") as? VolumeModule
    }

    var audioDevice: AudioDeviceModule? {
        manager.module(id: "audioDevice") as? AudioDeviceModule
    }

    var downloads: DownloadsModule? {
        manager.module(id: "downloads") as? DownloadsModule
    }

    var ci: CIModule? {
        manager.module(id: "ci") as? CIModule
    }
}
