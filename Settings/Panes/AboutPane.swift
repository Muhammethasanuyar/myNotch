import AppKit
import SwiftUI

/// Version, what leaves the Mac, and where the adapted code came from.
struct AboutPane: View {
    let openDebugPreview: @MainActor () -> Void
    let checkForUpdates: @MainActor () -> Void

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MyNotch")
                            .font(.title2.weight(.semibold))
                        Text(L("settings.about.version", "Version \(AppVersion.display)"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(L("settings.about.tagline", "The notch as a live surface: now playing, lyrics and Claude Code, a hover away."))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    Button(L("menu.checkForUpdates", "Check for Updates…")) {
                        checkForUpdates()
                    }
                    .controlSize(.small)
                    Link(L("settings.about.releases", "Release notes"), destination: URL(string: "https://github.com/Muhammethasanuyar/myNotch/releases")!)
                        .font(.callout)
                    Spacer()
                }
            }

            Section(L("settings.about.network", "What leaves this Mac")) {
                StatusRow(tone: .neutral, title: "LRCLIB", detail: L("settings.about.network.lrclib", "Artist, title, album and length of the current track, to fetch lyrics — only while lyrics are on."))
                StatusRow(tone: .neutral, title: "Spotify Web API", detail: L("settings.about.network.spotify", "The current track's ID, to read or set the heart — only after you connect your account."))
                StatusRow(tone: .neutral, title: "Anthropic", detail: L("settings.about.network.anthropic", "One usage request per poll interval with the Claude Code token, read from the CLI's Keychain item — never written, refreshed or logged."))
                StatusRow(tone: .neutral, title: "GitHub", detail: L("settings.about.network.github", "The update feed (appcast.xml in this project's repository), once a day, carrying the app and macOS versions — off with the switch in General."))
                SettingsFootnote(L("settings.about.network.none", "Nothing else: no analytics, no crash reports."))
            }

            Section(L("settings.about.credits", "Adapted from")) {
                Link("DynamicNotchKit — MIT", destination: URL(string: "https://github.com/MrKai77/DynamicNotchKit")!)
                Link("codex-island — MIT", destination: URL(string: "https://github.com/ericjypark/codex-island")!)
                Link("claude-notch-tracker — MIT", destination: URL(string: "https://github.com/stevemcqueenz/claude-notch-tracker")!)
                Link("ccusage — MIT", destination: URL(string: "https://github.com/ccusage/ccusage")!)
                SettingsFootnote(L("settings.about.credits.help", "Every adapted file names its source; the full licence texts ship in THIRD_PARTY_LICENSES.md."))
            }

            Section(L("settings.about.diagnostics", "Diagnostics")) {
                LabeledContent(L("settings.about.logs", "Live log")) {
                    CopyableText(text: "log stream --predicate 'subsystem == \"com.emre.mynotch\"'")
                }
                Button(L("settings.about.debugPreview", "Open Debug Preview")) {
                    openDebugPreview()
                }
            }
        }
    }
}
