import AppKit
import SwiftUI

/// Sign-in state, alert thresholds, polling cadence and the ccusage cost tool.
struct ClaudePane: View {
    @Bindable var store: SettingsStore
    let module: ClaudeUsageModule?

    var body: some View {
        if let module {
            content(service: module.service)
        } else {
            ContentUnavailableView(L("settings.claude.missing", "The Claude module is not registered."), systemImage: "asterisk")
        }
    }

    private func content(service: ClaudeUsageService) -> some View {
        SettingsForm {
            Section(L("settings.claude.account", "Account")) {
                authStatus(service)
                LabeledContent(L("settings.claude.lastReading", "Last reading")) {
                    Text(service.lastPollAt.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                        .foregroundStyle(.secondary)
                }
                Button(L("settings.claude.refresh", "Refresh now")) {
                    service.refreshUsage()
                }
                .disabled(service.isRefreshing)
                SettingsFootnote(L("settings.claude.account.help", "The token Claude Code stores in the Keychain is only read — never written, refreshed or logged. Sign in or out with the `claude` command."))
            }

            Section(L("settings.claude.alerts", "Alerts")) {
                Toggle(L("settings.claude.alerts.enabled", "Popup when a limit crosses a threshold"), isOn: $store.usageAlertsEnabled)
                    .toggleStyle(.switch)
                ValueSlider(
                    title: L("settings.claude.alerts.warning", "Warn at"),
                    value: $store.usageWarningThreshold,
                    range: SettingsRules.warningRange,
                    step: 0.05,
                    format: SettingsFormat.percent
                )
                ValueSlider(
                    title: L("settings.claude.alerts.critical", "Critical at"),
                    value: $store.usageCriticalThreshold,
                    range: SettingsRules.criticalRange,
                    step: 0.05,
                    format: SettingsFormat.percent
                )
                HStack {
                    Button(L("settings.claude.alerts.reset", "Reset thresholds")) {
                        store.resetThresholds()
                    }
                    .controlSize(.small)
                    Spacer()
                }
                SettingsFootnote(L("settings.claude.alerts.help", "Each window announces each threshold once; the rings turn orange and red at the same points."))
            }

            Section(L("settings.claude.polling", "Polling")) {
                Picker(L("settings.claude.polling.interval", "Ask Anthropic every"), selection: $store.usagePollInterval) {
                    ForEach(SettingsRules.pollIntervalChoices, id: \.self) { seconds in
                        Text(SettingsFormat.minutes(seconds)).tag(seconds)
                    }
                }
                SettingsFootnote(L("settings.claude.polling.help", "The limiter is shared with every Claude Code session on the account, so never more often than every 5 minutes; a rate limit pauses polling for 15 minutes."))
            }

            Section(L("settings.claude.cost", "Cost (ccusage)")) {
                costStatus(service.costState)
                HStack(spacing: 8) {
                    TextField(L("settings.claude.cost.path", "ccusage path"), text: $store.ccusagePath, prompt: Text(L("settings.claude.cost.path.prompt", "Auto-detect (Homebrew, npm, bun, npx)")))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button(L("settings.claude.cost.choose", "Choose…")) {
                        chooseCCUsage()
                    }
                }
                SettingsFootnote(L("settings.claude.cost.help", "ccusage reads the session logs locally and always runs offline; the version is pinned to ccusage@20. Install with `brew install ccusage` or `npm i -g ccusage`."))
            }

            Section(L("settings.claude.advanced", "Advanced")) {
                TextField(L("settings.claude.configDir", "Claude config directory"), text: $store.claudeConfigDir, prompt: Text(L("settings.claude.configDir.prompt", "~/.claude, or $CLAUDE_CONFIG_DIR")))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                SettingsFootnote(L("settings.claude.configDir.help", "Where Claude Code keeps its credentials and session logs. Changing it restarts the module."))
            }
        }
    }

    private func authStatus(_ service: ClaudeUsageService) -> some View {
        let (tone, title, detail): (StatusTone, String, String?) = switch service.auth {
        case .ok:
            (.ok, L("settings.claude.auth.ok", "Signed in"), service.subscriptionType)
        case .signedOut:
            (.attention, L("settings.claude.auth.signedOut", "Not signed in"), L("settings.claude.auth.signedOut.help", "Run `claude` in Terminal and sign in; the notch picks it up within seconds."))
        case .tokenExpired:
            (.attention, L("settings.claude.auth.expired", "Token expired"), L("settings.claude.auth.expired.help", "Any `claude` command refreshes it."))
        case .reauthRequired:
            (.problem, L("settings.claude.auth.reauth", "Sign-in needed again"), L("settings.claude.auth.reauth.help", "Run `claude /login`."))
        case .rateLimited(let until):
            (.attention, L("settings.claude.auth.rateLimited", "Rate limited"), L("settings.claude.auth.rateLimited.help", "Polling resumes \(until.formatted(.relative(presentation: .named)))."))
        case .unreachable(let message):
            (.problem, L("settings.claude.auth.unreachable", "Anthropic unreachable"), message)
        }
        return StatusRow(tone: tone, title: title, detail: detail)
    }

    private func costStatus(_ state: CCUsageState) -> some View {
        let (tone, title, detail): (StatusTone, String, String?) = switch state {
        case .unknown:
            (.pending, L("settings.claude.cost.unknown", "Looking for ccusage…"), nil)
        case .ready(let launcher):
            (.ok, L("settings.claude.cost.ready", "ccusage found"), launcher.description)
        case .notInstalled:
            (.attention, L("settings.claude.cost.notInstalled", "ccusage not installed"), L("settings.claude.cost.notInstalled.help", "Cost stays hidden; the limits still work."))
        case .failed(let message):
            (.problem, L("settings.claude.cost.failed", "ccusage failed"), message)
        }
        return StatusRow(tone: tone, title: title, detail: detail)
    }

    private func chooseCCUsage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = L("settings.claude.cost.choose.message", "Pick the ccusage executable")
        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            store.ccusagePath = url.path
        }
    }
}
