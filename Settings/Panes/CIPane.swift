import SwiftUI

/// Xcode builds on this Mac and GitHub Actions runs through the user's own `gh`.
struct CIPane: View {
    @Bindable var store: SettingsStore
    let module: CIModule?

    var body: some View {
        if let module {
            content(module)
        } else {
            ContentUnavailableView(L("settings.ci.missing", "The builds module is not registered."), systemImage: "hammer")
        }
    }

    private func content(_ module: CIModule) -> some View {
        SettingsForm {
            if !store.isModuleEnabled(module.id) {
                Section {
                    StatusRow(tone: .neutral, title: L("settings.ci.off", "Off"), detail: L("settings.ci.off.help", "Turn the module on under Modules; nothing is watched or run until then."))
                }
            }

            Section(L("settings.ci.xcode", "Xcode")) {
                Toggle(L("settings.ci.xcode.enabled", "Report finished Xcode builds"), isOn: $store.ciXcodeEnabled)
                    .toggleStyle(.switch)
                StatusRow(tone: .neutral, title: XcodeBuildWatcher.defaultRoot.path(percentEncoded: false), detail: L("settings.ci.xcode.help", "Read from the build-log manifests Xcode keeps under DerivedData; a build that finishes posts a popup with its result."))
            }

            Section(L("settings.ci.github", "GitHub Actions")) {
                githubStatus(module.service.github)
                TextField(L("settings.ci.repos", "Repositories"), text: $store.ciRepos, prompt: Text("owner/repo, owner/other"))
                    .textFieldStyle(.roundedBorder)
                Picker(L("settings.ci.poll", "Ask GitHub every"), selection: $store.ciPollInterval) {
                    ForEach(CIRules.pollChoices, id: \.self) { seconds in
                        Text(SettingsFormat.minutes(seconds)).tag(seconds)
                    }
                }
                TextField(L("settings.ci.ghPath", "gh path (optional)"), text: $store.ciGHPath, prompt: Text("/opt/homebrew/bin/gh"))
                    .textFieldStyle(.roundedBorder)
                SettingsFootnote(L("settings.ci.github.help", "Up to five owner/repo entries. MyNotch runs your own gh command line tool and stores no token: gh sends its own credentials, and only the run list comes back. Polled at the chosen rate while a run is in flight or the card is open, every ten minutes otherwise, never with no repositories."))
            }
        }
    }

    @ViewBuilder
    private func githubStatus(_ service: GitHubRunsService) -> some View {
        switch service.state {
        case .off:
            StatusRow(tone: .neutral, title: L("settings.ci.github.off", "No repositories"), detail: L("settings.ci.github.off.help", "Add owner/repo below to watch its Actions runs."))
        case .missing:
            StatusRow(tone: .attention, title: L("settings.ci.github.missing", "GitHub CLI not found"), detail: L("settings.ci.github.missing.help", "Install it with Homebrew, or point the path field at it."))
            LabeledContent(L("settings.ci.install", "Install")) {
                CopyableText(text: "brew install gh && gh auth login")
            }
        case .notAuthenticated:
            StatusRow(tone: .attention, title: L("settings.ci.github.auth", "gh is not signed in"), detail: L("settings.ci.github.auth.help", "Run gh auth login in Terminal, then try again."))
            HStack {
                Button(L("settings.ci.retry", "Try again")) { service.refresh() }
                    .controlSize(.small)
                Spacer()
            }
        case .ready:
            StatusRow(
                tone: service.repoErrors.isEmpty ? .ok : .attention,
                title: L("settings.ci.github.ready", "Watching \(service.repos.count) repositories"),
                detail: service.repoErrors.isEmpty ? nil : service.repoErrors.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
            )
        case .failed(let message):
            StatusRow(tone: .problem, title: L("settings.ci.github.failed", "gh could not list runs"), detail: message)
            HStack {
                Button(L("settings.ci.retry", "Try again")) { service.refresh() }
                    .controlSize(.small)
                Spacer()
            }
        }
    }
}
