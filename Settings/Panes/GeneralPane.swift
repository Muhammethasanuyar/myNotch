import AppKit
import SwiftUI

/// Startup, the notch's timing and which display it lives on.
struct GeneralPane: View {
    @Bindable var store: SettingsStore
    let launchAtLogin: LaunchAtLogin

    @State private var connectedScreens: [String] = NSScreen.screens.map(\.localizedName)

    var body: some View {
        SettingsForm {
            Section(L("settings.general.startup", "Startup")) {
                Toggle(isOn: launchBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.general.launchAtLogin", "Launch at login"))
                        SettingsFootnote(launchDetail)
                    }
                }
                .toggleStyle(.switch)
                if launchAtLogin.state == .requiresApproval {
                    Button(L("settings.general.openLoginItems", "Open Login Items…")) {
                        LaunchAtLogin.openSystemSettings()
                    }
                    .controlSize(.small)
                }
                if let error = launchAtLogin.lastError {
                    StatusRow(tone: .problem, title: L("settings.general.launchFailed", "Could not change the login item"), detail: error)
                }
            }

            Section(L("settings.general.notch", "Notch")) {
                ValueSlider(
                    title: L("settings.general.hoverDelay", "Open after hovering for"),
                    value: $store.hoverDelay,
                    range: SettingsRules.hoverDelayRange,
                    step: 0.05,
                    format: SettingsFormat.seconds
                )
                ValueSlider(
                    title: L("settings.general.closeDelay", "Stay open after leaving for"),
                    value: $store.closeDelay,
                    range: SettingsRules.closeDelayRange,
                    step: 0.1,
                    format: SettingsFormat.seconds
                )
                SettingsFootnote(L("settings.general.closeDelay.help", "Applies while the pointer is still near the card; moving further away closes it at once."))
                Toggle(L("settings.general.haptics", "Haptic feedback when the notch opens"), isOn: $store.hapticsEnabled)
                    .toggleStyle(.switch)
            }

            Section(L("settings.general.updates", "Updates")) {
                Toggle(L("settings.general.updates.enabled", "Check for updates once a day"), isOn: $store.updateChecksEnabled)
                    .toggleStyle(.switch)
                SettingsFootnote(L("settings.general.updates.help", "Reads the appcast in the project's GitHub repository; only the app and macOS versions travel. A new version is offered with its notes and installed only when you say so. \"Check for Updates…\" in the menu bar works either way."))
            }

            Section(L("settings.general.display", "Display")) {
                Picker(L("settings.general.displayPicker", "Show the notch on"), selection: $store.displaySelection) {
                    Text(L("settings.general.display.automatic", "Automatic")).tag(ScreenPreference.automatic)
                    ForEach(screenChoices, id: \.self) { name in
                        Text(connectedScreens.contains(name) ? name : L("settings.general.display.disconnected", "\(name) (not connected)"))
                            .tag(ScreenPreference.named(name))
                    }
                }
                SettingsFootnote(L("settings.general.display.help", "Automatic uses the display with a notch, or the main display without one. On a display without a notch the surface floats below the top edge."))
            }

            Section {
                Button(L("settings.general.reset", "Reset to defaults")) {
                    store.resetEngineDefaults()
                }
            }
        }
        .onAppear { launchAtLogin.refresh() }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                connectedScreens = NSScreen.screens.map(\.localizedName)
            }
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.state.isOn },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var launchDetail: String {
        switch launchAtLogin.state {
        case .enabled:
            L("settings.general.launch.enabled", "MyNotch starts when you log in.")
        case .disabled:
            L("settings.general.launch.disabled", "Start MyNotch in the menu bar when you log in.")
        case .requiresApproval:
            L("settings.general.launch.approval", "Waiting for your approval in System Settings → General → Login Items.")
        case .notFound:
            L("settings.general.launch.notFound", "The system cannot see this copy of MyNotch. Move it to Applications and try again.")
        }
    }

    /// Connected displays plus the one stored, so a chosen display that is unplugged keeps its entry.
    private var screenChoices: [String] {
        var names = connectedScreens
        if case .named(let stored) = store.displaySelection, !names.contains(stored) {
            names.append(stored)
        }
        return names
    }
}
