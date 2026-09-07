import SwiftUI

/// First-run checklist: every permission and sign-in the modules can use, each with its one action.
/// Nothing here is required; the notch works with whatever is green.
struct SetupPane: View {
    let context: SettingsContext
    @Bindable var navigation: SettingsNavigation
    let closeWindow: @MainActor () -> Void

    var body: some View {
        SettingsForm {
            Section {
                Text(L("settings.setup.intro", "MyNotch only shows what other apps already know. Each row is one permission or sign-in; the notch works with whichever are green."))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L("settings.setup.players", "Players")) {
                if let media = context.media {
                    automationRow(media.controller)
                    spotifyRow(media.controller)
                }
            }

            Section(L("settings.setup.claude", "Claude Code")) {
                if let claude = context.claude {
                    signInRow(claude.service)
                    logsRow(claude.service)
                    ccusageRow(claude.service)
                }
            }

            Section(L("settings.setup.calendarSection", "Calendar")) {
                if let calendar = context.calendar {
                    calendarRow(calendar.service)
                }
            }

            Section(L("settings.setup.system", "System")) {
                loginRow
                if let shelf = context.shelf {
                    shelfRow(shelf.store)
                }
                if let volume = context.volume, context.store.volumeHUDReplacement {
                    volumeRow(volume.service)
                }
                if let downloads = context.downloads {
                    downloadsRow(downloads)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button(context.store.onboardingCompleted ? L("settings.setup.close", "Close") : L("settings.setup.done", "Done")) {
                        context.store.onboardingCompleted = true
                        closeWindow()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { context.launchAtLogin.refresh() }
    }

    // MARK: Rows

    private func automationRow(_ controller: MediaController) -> some View {
        let tone: StatusTone = switch controller.permission {
        case .unknown: .neutral
        case .granted: .ok
        case .denied: .problem
        }
        return SetupRow(
            tone: tone,
            title: L("settings.setup.automation", "Control Spotify and Music"),
            detail: controller.permission == .granted
                ? L("settings.setup.automation.ok", "Allowed. Playback, artwork and lyrics work.")
                : L("settings.setup.automation.todo", "macOS asks the first time a player is running. If you declined, allow MyNotch under Automation."),
            actionTitle: controller.permission == .denied
                ? L("settings.media.automation.open", "Open Privacy Settings…")
                : L("settings.media.automation.check", "Check again")
        ) {
            if controller.permission == .denied {
                SystemSettingsLink.open(SystemSettingsLink.automation)
            } else {
                controller.refresh()
            }
        }
    }

    private func spotifyRow(_ controller: MediaController) -> some View {
        let connected = controller.spotifyLibrary?.connection == .connected
        return SetupRow(
            tone: connected ? .ok : .neutral,
            title: L("settings.setup.spotify", "Spotify library (optional)"),
            detail: connected
                ? L("settings.setup.spotify.ok", "Connected. The heart shows and toggles your library.")
                : L("settings.setup.spotify.todo", "Lets the heart in the player save tracks. Needs a free Spotify developer app."),
            actionTitle: connected ? nil : L("settings.setup.goTo.media", "Set up in Media…")
        ) {
            navigation.selectedTab = .media
        }
    }

    private func signInRow(_ service: ClaudeUsageService) -> some View {
        let ok = service.auth == .ok
        return SetupRow(
            tone: ok ? .ok : .attention,
            title: L("settings.setup.signIn", "Claude Code sign-in"),
            detail: ok
                ? L("settings.setup.signIn.ok", "Signed in. Limits are read from Anthropic every few minutes.")
                : L("settings.setup.signIn.todo", "Run `claude` in Terminal and sign in. MyNotch reads the CLI's token; it never stores one itself."),
            actionTitle: L("settings.claude.refresh", "Refresh now")
        ) {
            service.refreshUsage()
        }
    }

    private func logsRow(_ service: ClaudeUsageService) -> some View {
        SetupRow(
            tone: service.hasLogs ? .ok : .neutral,
            title: L("settings.setup.logs", "Session logs"),
            detail: service.hasLogs
                ? L("settings.setup.logs.ok", "Found. The pulse and today's blocks come from here.")
                : L("settings.setup.logs.todo", "Appear after the first Claude Code session on this Mac."),
            actionTitle: nil
        ) {}
    }

    private func ccusageRow(_ service: ClaudeUsageService) -> some View {
        let ready = if case .ready = service.costState { true } else { false }
        return SetupRow(
            tone: ready ? .ok : .neutral,
            title: L("settings.setup.ccusage", "Cost (optional)"),
            detail: ready
                ? L("settings.setup.ccusage.ok", "ccusage found. Today's spend appears on the card.")
                : L("settings.setup.ccusage.todo", "Tokens and blocks work without it; install ccusage (`brew install ccusage`) to see today's spend. Runs offline."),
            actionTitle: ready ? nil : L("settings.setup.goTo.claude", "Set up in Claude…")
        ) {
            navigation.selectedTab = .claude
        }
    }

    private func calendarRow(_ service: CalendarService) -> some View {
        let (tone, detail, actionTitle): (StatusTone, String, String?) = switch service.access {
        case .authorized:
            (.ok, L("settings.setup.calendar.ok", "Allowed. The next meeting shows up in the notch when it is close."), nil)
        case .notDetermined:
            (.neutral, L("settings.setup.calendar.todo", "Optional. Lets the notch count down to the next meeting and open its link."), L("settings.calendar.grant", "Grant access…"))
        case .denied, .restricted:
            (.problem, L("settings.setup.calendar.denied", "Denied. Allow MyNotch under Privacy & Security → Calendars."), L("settings.calendar.openPrivacy", "Open Privacy Settings…"))
        }
        return SetupRow(tone: tone, title: L("settings.setup.calendar", "Calendar (optional)"), detail: detail, actionTitle: actionTitle) {
            if service.access == .notDetermined {
                Task { await service.requestAccess() }
            } else {
                SystemSettingsLink.open(SystemSettingsLink.calendars)
            }
        }
    }

    private func shelfRow(_ shelf: ShelfStore) -> some View {
        SetupRow(
            tone: shelf.items.isEmpty ? .neutral : .ok,
            title: L("settings.setup.shelf", "Shelf (optional)"),
            detail: shelf.items.isEmpty
                ? L("settings.setup.shelf.todo", "Drag a file onto the notch: it opens, keeps a copy for a while and can AirDrop it.")
                : L("settings.setup.shelf.ok", "Files are on the shelf. Copies live in Application Support and expire on their own."),
            actionTitle: L("settings.setup.shelf.open", "Shelf settings…")
        ) {
            navigation.selectedTab = .shelf
        }
    }

    private func volumeRow(_ service: VolumeService) -> some View {
        let (tone, detail, actionTitle): (StatusTone, String, String?) = switch service.tapState {
        case .running:
            (.ok, L("settings.setup.volume.ok", "Allowed. Volume keys open the notch instead of the system HUD."), nil)
        case .needsPermission:
            (.attention, L("settings.setup.volume.todo", "Needs Accessibility so MyNotch can read the volume keys before macOS does. The grant is tied to the app's signature."), L("settings.sound.hud.grant", "Grant access…"))
        case .failed:
            (.problem, L("settings.setup.volume.failed", "The key tap could not start; the system HUD is showing."), L("settings.sound.hud.retry", "Try again"))
        case .off:
            (.pending, L("settings.setup.volume.starting", "Starting…"), nil)
        }
        return SetupRow(tone: tone, title: L("settings.setup.volume", "Volume keys (optional)"), detail: detail, actionTitle: actionTitle) {
            if service.tapState == .needsPermission {
                service.requestAccessibility()
            } else {
                service.syncTap()
            }
        }
    }

    private func downloadsRow(_ module: DownloadsModule) -> some View {
        let enabled = context.store.isModuleEnabled(module.id)
        let (tone, detail, actionTitle): (StatusTone, String, String?) = if !enabled {
            (.neutral, L("settings.setup.downloads.off", "Optional. Shows browser downloads in the notch; needs permission to read the Downloads folder."), L("settings.setup.downloads.enable", "Turn on"))
        } else {
            switch module.service.access {
            case .granted: (.ok, L("settings.setup.downloads.ok", "Allowed. Downloads show up in the notch while they run."), nil)
            case .unknown: (.pending, L("settings.setup.downloads.checking", "Checking the folder…"), L("settings.downloads.retry", "Try again"))
            case .denied: (.problem, L("settings.setup.downloads.denied", "Denied. Allow MyNotch under Privacy & Security → Files and Folders → Downloads."), L("settings.downloads.openPrivacy", "Open Privacy Settings…"))
            }
        }
        return SetupRow(tone: tone, title: L("settings.setup.downloads", "Downloads (optional)"), detail: detail, actionTitle: actionTitle) {
            if !enabled {
                context.store.setModule(module.id, enabled: true)
            } else if module.service.access == .denied {
                SystemSettingsLink.open(SystemSettingsLink.filesAndFolders)
            } else {
                module.service.requestAccess()
            }
        }
    }

    private var loginRow: some View {
        let state = context.launchAtLogin.state
        let detail: String = switch state {
        case .enabled: L("settings.general.launch.enabled", "MyNotch starts when you log in.")
        case .requiresApproval: L("settings.general.launch.approval", "Waiting for your approval in System Settings → General → Login Items.")
        case .disabled, .notFound: L("settings.setup.login.todo", "Turn it on so the notch is there after a restart.")
        }
        let actionTitle: String? = switch state {
        case .enabled: nil
        case .requiresApproval: L("settings.general.openLoginItems", "Open Login Items…")
        case .disabled, .notFound: L("settings.setup.login.enable", "Turn on")
        }
        return SetupRow(
            tone: state == .enabled ? .ok : (state == .requiresApproval ? .attention : .neutral),
            title: L("settings.setup.login", "Launch at login (optional)"),
            detail: detail,
            actionTitle: actionTitle
        ) {
            if state == .requiresApproval {
                LaunchAtLogin.openSystemSettings()
            } else {
                context.launchAtLogin.setEnabled(true)
            }
        }
    }
}

/// A checklist line: status, explanation and at most one button.
private struct SetupRow: View {
    let tone: StatusTone
    let title: String
    let detail: String
    let actionTitle: String?
    let action: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusRow(tone: tone, title: title, detail: detail)
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
