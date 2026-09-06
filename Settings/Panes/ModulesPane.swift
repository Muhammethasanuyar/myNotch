import SwiftUI

/// One switch per registered module.
struct ModulesPane: View {
    let store: SettingsStore
    let manager: ModuleManager

    var body: some View {
        SettingsForm {
            Section(L("settings.modules.section", "Modules")) {
                ForEach(manager.snapshots, id: \.id) { snapshot in
                    Toggle(isOn: binding(for: snapshot.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: ModuleCatalog.symbolName(for: snapshot.id))
                                .font(.title3)
                                .frame(width: 24)
                                .foregroundStyle(snapshot.isEnabled ? .primary : .tertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manager.module(id: snapshot.id)?.displayName ?? snapshot.id)
                                SettingsFootnote(ModuleCatalog.summary(for: snapshot.id))
                            }
                            Spacer(minLength: 8)
                            if snapshot.isEnabled {
                                ActivityPill(activity: snapshot.activity)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
            SettingsFootnote(L("settings.modules.help", "A module that is off does nothing at all: no scripts, no network requests, no popups. Its screen leaves the switcher under the card."))
        }
    }

    private func binding(for moduleID: String) -> Binding<Bool> {
        Binding(
            get: { store.isModuleEnabled(moduleID) },
            set: { store.setModule(moduleID, enabled: $0) }
        )
    }
}

/// What the module is doing right now, in the notch's own terms.
private struct ActivityPill: View {
    let activity: ModuleActivity

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .animation(.default, value: activity)
    }

    private var title: String {
        switch activity {
        case .idle: L("settings.modules.activity.idle", "Idle")
        case .live: L("settings.modules.activity.live", "Live")
        case .urgent: L("settings.modules.activity.urgent", "Alert")
        }
    }

    private var color: Color {
        switch activity {
        case .idle: .secondary
        case .live: .green
        case .urgent: .orange
        }
    }
}

/// Icons and one-line summaries for the modules the app ships with.
nonisolated enum ModuleCatalog {
    static func symbolName(for moduleID: String) -> String {
        switch moduleID {
        case "media": "music.note"
        case "claude": "asterisk"
        case "battery": "battery.100percent.bolt"
        case "pomodoro": "timer"
        case "calendar": "calendar"
        case "shelf": "tray.full.fill"
        case "demo": "wand.and.stars"
        default: "puzzlepiece.extension"
        }
    }

    static func summary(for moduleID: String) -> String {
        switch moduleID {
        case "media":
            L("settings.modules.media.summary", "Now playing from Spotify and Music, synced lyrics, your Spotify library heart.")
        case "claude":
            L("settings.modules.claude.summary", "Claude Code limits, today's cost and a pulse while it works.")
        case "battery":
            L("settings.modules.battery.summary", "Charging and low-battery popups, a gauge while it matters.")
        case "pomodoro":
            L("settings.modules.pomodoro.summary", "A focus timer: ring beside the housing, controls on the card, a chime between phases.")
        case "calendar":
            L("settings.modules.calendar.summary", "The next meeting: a countdown when it is close, popups before it starts, a Join button.")
        case "shelf":
            L("settings.modules.shelf.summary", "Drag files onto the notch to keep a copy for a while, then AirDrop them or drag them on.")
        case "demo":
            L("settings.modules.demo.summary", "Exercises the notch engine; Debug builds only.")
        default:
            ""
        }
    }
}
