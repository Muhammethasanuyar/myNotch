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
            Section(L("settings.media.visualizer", "Level meter")) {
                Toggle(L("settings.media.visualizer.enabled", "Move the bars to the music"), isOn: $store.visualizerEnabled)
                    .toggleStyle(.switch)
                visualizerStatus(controller.audioMeter.state)
                if controller.audioMeter.state == .silent {
                    HStack {
                        Button(L("settings.media.visualizer.openPrivacy", "Open Privacy Settings…")) {
                            SystemSettingsLink.open(SystemSettingsLink.screenAudio)
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                }
                SettingsFootnote(L("settings.media.visualizer.help", "Taps what the Mac plays (macOS 14.2 or later) and reduces it to six band levels inside the app; no audio is stored or sent. macOS asks once for system-audio recording permission. Off, the bars keep their own rhythm."))
            }

            Section(L("settings.media.generic", "Other players")) {
                Toggle(L("settings.media.generic.enabled", "Show whatever the Mac is playing"), isOn: $store.genericPlayerEnabled)
                    .toggleStyle(.switch)
                if let generic = controller.genericPlayer {
                    genericStatus(generic)
                    HStack {
                        Button(L("settings.media.generic.recheck", "Test again")) {
                            controller.recheckGenericPlayer()
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                }
                SettingsFootnote(L("settings.media.generic.help", "Safari, Chrome, IINA, podcast apps — anything that publishes to Now Playing. Uses the bundled mediaremote-adapter: perl loads a private Apple framework in a separate process, so a macOS update can break it; a health check runs once per version and the notch falls back to Spotify and Music if it does. Nothing leaves this Mac."))
            }

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

    private func genericStatus(_ generic: GenericNowPlayingProvider) -> some View {
        let (tone, title): (StatusTone, String) = switch generic.health {
        case .unchecked:
            store.genericPlayerEnabled
                ? (.pending, L("settings.media.generic.checking", "Checking the adapter…"))
                : (.neutral, L("settings.media.generic.off", "Off"))
        case .ok:
            generic.isStreaming
                ? (generic.snapshot == nil
                    ? (.ok, L("settings.media.generic.idle", "Listening — nothing playing elsewhere"))
                    : (.ok, L("settings.media.generic.playing", "Following \(generic.displayName)")))
                : (.neutral, L("settings.media.generic.ready", "Adapter works; turn the switch on to use it"))
        case .artefactsMissing: (.problem, L("settings.media.generic.missing", "This build has no adapter bundled"))
        case .testClientFailed, .setupTimeout: (.problem, L("settings.media.generic.testFailed", "The adapter's self-test could not run"))
        case .noData: (.problem, L("settings.media.generic.noData", "macOS no longer lets the adapter read Now Playing"))
        case .broken(let code): (.problem, L("settings.media.generic.broken", "The adapter stopped (exit \(code)); Spotify and Music still work"))
        case .timedOut: (.attention, L("settings.media.generic.timedOut", "The self-test timed out"))
        }
        return StatusRow(tone: tone, title: title)
    }

    private func visualizerStatus(_ state: AudioMeterState) -> some View {
        let (tone, title): (StatusTone, String) = switch state {
        case .off: (.neutral, store.visualizerEnabled ? L("settings.media.visualizer.idle", "Waiting for music") : L("settings.media.visualizer.off", "Off — the bars dance on their own"))
        case .unsupported: (.attention, L("settings.media.visualizer.unsupported", "Needs macOS 14.2 or later"))
        case .starting: (.pending, L("settings.media.visualizer.starting", "Starting the tap…"))
        case .running: (.ok, L("settings.media.visualizer.running", "Following the sound"))
        case .silent: (.attention, L("settings.media.visualizer.silent", "Hearing nothing — allow MyNotch under Privacy & Security → Screen & System Audio Recording"))
        case .failed(let status): (.problem, L("settings.media.visualizer.failed", "The tap could not start (\(status))"))
        }
        return StatusRow(tone: tone, title: title)
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
