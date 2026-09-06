import AppKit
import SwiftUI

/// Lyrics, the Spotify library connection and the Automation permission the players need.
struct MediaPane: View {
    @Bindable var store: SettingsStore
    let module: MediaModule?

    var body: some View {
        if let module {
            content(controller: module.controller)
        } else {
            ContentUnavailableView(L("settings.media.missing", "The media module is not registered."), systemImage: "music.note.list")
        }
    }

    private func content(controller: MediaController) -> some View {
        SettingsForm {
            Section(L("settings.media.lyrics", "Lyrics")) {
                Toggle(L("settings.media.lyrics.enabled", "Show synced lyrics"), isOn: $store.lyricsEnabled)
                    .toggleStyle(.switch)
                ValueSlider(
                    title: L("settings.media.lyrics.lead", "Lyrics run ahead of the audio by"),
                    value: $store.lyricsLeadSeconds,
                    range: -0.5...0.5,
                    step: 0.05,
                    format: SettingsFormat.signedMilliseconds
                )
                .disabled(!store.lyricsEnabled)
                SettingsFootnote(L("settings.media.lyrics.lead.help", "A small lead reads best. Bluetooth headphones delay the sound; a negative value holds the lyrics back to match. The ± buttons on the player adjust one song at a time."))
                HStack {
                    Button(L("settings.media.lyrics.forgetShifts", "Forget per-song adjustments")) {
                        store.resetLyricsShifts()
                    }
                    .disabled(controller.lyrics.shifts.isEmpty)
                    Text(L("settings.media.lyrics.shiftCount", "\(controller.lyrics.shifts.count) songs"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SettingsFootnote(L("settings.media.lyrics.privacy", "Lyrics come from LRCLIB (lrclib.net). Only the artist, title, album and length of the current track are sent, and only while lyrics are on."))
            }

            Section(L("settings.media.spotify", "Spotify library")) {
                TextField(L("settings.media.spotify.clientID", "Client ID"), text: $store.spotifyClientID, prompt: Text(L("settings.media.spotify.clientID.prompt", "From your app in the Spotify Developer Dashboard")))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                LabeledContent(L("settings.media.spotify.redirect", "Redirect URI")) {
                    CopyableText(text: SpotifyPKCE.redirectURI)
                }
                if let library = controller.spotifyLibrary {
                    spotifyStatus(library)
                    HStack(spacing: 8) {
                        Button(L("settings.media.spotify.connect", "Connect…")) {
                            library.connect()
                        }
                        .disabled(library.connection != .disconnected)
                        Button(L("settings.media.spotify.disconnect", "Disconnect")) {
                            library.disconnect()
                        }
                        .disabled(library.connection == .notConfigured || library.connection == .disconnected)
                        Spacer()
                        Link(L("settings.media.spotify.dashboard", "Spotify Developer Dashboard"), destination: URL(string: "https://developer.spotify.com/dashboard")!)
                            .font(.callout)
                    }
                }
                SettingsFootnote(L("settings.media.spotify.privacy", "Create a free app in the dashboard, paste its client ID here and add the redirect URI above. Only the ID of the current track is sent to Spotify, and only while connected. Tokens live in Application Support in a file only you can read."))
            }

            Section(L("settings.media.automation", "Automation permission")) {
                automationStatus(controller.permission)
                HStack(spacing: 8) {
                    Button(L("settings.media.automation.open", "Open Privacy Settings…")) {
                        SystemSettingsLink.open(SystemSettingsLink.automation)
                    }
                    Button(L("settings.media.automation.check", "Check again")) {
                        controller.refresh()
                    }
                }
                SettingsFootnote(L("settings.media.automation.help", "MyNotch asks Spotify and Music what is playing through AppleScript. macOS shows the permission prompt the first time a player is running."))
            }
        }
    }

    private func spotifyStatus(_ library: SpotifyLibraryClient) -> some View {
        let (tone, title): (StatusTone, String) = switch library.connection {
        case .notConfigured: (.attention, L("settings.media.spotify.notConfigured", "Enter a client ID to enable the heart"))
        case .disconnected: (.neutral, L("settings.media.spotify.disconnected", "Not connected"))
        case .connecting: (.pending, L("settings.media.spotify.connecting", "Waiting for Spotify in your browser…"))
        case .connected: (.ok, L("settings.media.spotify.connected", "Connected — the heart reflects your library"))
        }
        return StatusRow(tone: library.lastError == nil ? tone : .problem, title: title, detail: library.lastError)
    }

    private func automationStatus(_ permission: MediaPermission) -> some View {
        let (tone, title): (StatusTone, String) = switch permission {
        case .unknown: (.neutral, L("settings.media.automation.unknown", "Not asked yet — start Spotify or Music"))
        case .granted: (.ok, L("settings.media.automation.granted", "Allowed for Spotify and Music"))
        case .denied: (.problem, L("settings.media.automation.denied", "Denied — allow MyNotch under Automation, then check again"))
        }
        return StatusRow(tone: tone, title: title)
    }
}
