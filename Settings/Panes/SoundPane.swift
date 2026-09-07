import SwiftUI

/// The output level in the notch, and whether the volume keys go there instead of to the system HUD.
struct SoundPane: View {
    @Bindable var store: SettingsStore
    let volume: VolumeModule?
    let audioDevice: AudioDeviceModule?

    var body: some View {
        SettingsForm {
            Section(L("settings.sound.device", "Output device")) {
                if let audioDevice {
                    deviceStatus(audioDevice.service)
                }
                Toggle(L("settings.sound.device.connect", "Popup when headphones, speakers or a display take over"), isOn: $store.audioDeviceConnectPopups)
                    .toggleStyle(.switch)
                Toggle(L("settings.sound.device.disconnect", "Popup when the sound comes back to the built-in speakers"), isOn: $store.audioDeviceDisconnectPopups)
                    .toggleStyle(.switch)
                Toggle(L("settings.sound.device.battery", "Show the AirPods battery"), isOn: $store.audioDeviceBatteryEnabled)
                    .toggleStyle(.switch)
                SettingsFootnote(L("settings.sound.device.help", "Core Audio says which device is the default output; the popup names it with its glyph. The battery comes from the IORegistry, which AirPods fill in a few seconds after connecting — read only, no Bluetooth permission involved."))
            }

            Section(L("settings.sound.volume", "Volume")) {
                if let volume {
                    levelStatus(volume.service)
                }
                Toggle(L("settings.sound.popups", "Show the level in the notch when it changes"), isOn: $store.volumePopupsEnabled)
                    .toggleStyle(.switch)
                SettingsFootnote(L("settings.sound.popups.help", "A short popup for volume and mute changes made anywhere — the keys, the menu bar, another app. No permission involved; macOS still shows its own HUD."))
            }

            Section(L("settings.sound.hud", "Volume keys")) {
                Toggle(L("settings.sound.hud.enabled", "Replace the system volume HUD"), isOn: $store.volumeHUDReplacement)
                    .toggleStyle(.switch)
                if let volume, store.volumeHUDReplacement {
                    hudStatus(volume.service)
                }
                SettingsFootnote(L("settings.sound.hud.help", "MyNotch takes the volume and mute keys before macOS does, moves the level in sixteenths (Option-Shift: quarters, Shift: with the feedback sound) and shows it in the notch, so the system HUD never appears. Needs the Accessibility permission, which macOS ties to the app's signature: a rebuilt or re-signed app asks again. Brightness keys are never touched, and a device without a volume (HDMI, optical) keeps its system behaviour."))
            }
        }
    }

    private func deviceStatus(_ service: AudioDeviceService) -> some View {
        guard let output = service.output else {
            return StatusRow(tone: .neutral, title: L("audioDevice.none", "No output device"))
        }
        var detail = AudioDeviceRules.transportName(output.transport)
        if let battery = service.battery, let text = AudioDeviceRules.batteryText(battery) {
            detail += " · " + text
        }
        return StatusRow(tone: AudioDeviceRules.isExternal(output) ? .ok : .neutral, title: output.name, detail: detail)
    }

    private func levelStatus(_ service: VolumeService) -> some View {
        let snapshot = service.snapshot
        return StatusRow(
            tone: snapshot == nil ? .neutral : (snapshot!.hasVolumeControl ? .ok : .neutral),
            title: snapshot.map { VolumeRules.levelText($0) } ?? L("volume.noDevice", "No output device"),
            detail: snapshot?.deviceName
        )
    }

    @ViewBuilder
    private func hudStatus(_ service: VolumeService) -> some View {
        switch service.tapState {
        case .off:
            StatusRow(tone: .pending, title: L("settings.sound.hud.starting", "Starting…"))
        case .needsPermission:
            StatusRow(tone: .attention, title: L("settings.sound.hud.permission", "Needs Accessibility to read the keys before macOS does"))
            HStack(spacing: 8) {
                Button(L("settings.sound.hud.grant", "Grant access…")) { service.requestAccessibility() }
                    .controlSize(.small)
                Button(L("settings.sound.hud.openPrivacy", "Open Privacy Settings…")) { SystemSettingsLink.open(SystemSettingsLink.accessibility) }
                    .controlSize(.small)
                Button(L("settings.sound.hud.recheck", "Check again")) { service.syncTap() }
                    .controlSize(.small)
                Spacer()
            }
        case .running:
            StatusRow(
                tone: .ok,
                title: L("settings.sound.hud.running", "On — volume keys go to the notch"),
                detail: service.tapReEnables > 0 ? L("settings.sound.hud.reenabled", "macOS paused the key tap \(service.tapReEnables) time(s); it came back on its own.") : nil
            )
        case .failed(let message):
            StatusRow(tone: .problem, title: L("settings.sound.hud.failed", "The key tap could not start"), detail: message)
            HStack {
                Button(L("settings.sound.hud.retry", "Try again")) { service.syncTap() }
                    .controlSize(.small)
                Spacer()
            }
        }
    }
}
