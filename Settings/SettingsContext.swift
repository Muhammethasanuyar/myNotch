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
}
