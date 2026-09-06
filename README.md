# MyNotch

MyNotch turns the MacBook notch into a live surface, in the spirit of the iPhone's Dynamic Island. It is a menu-bar app: the housing stays black until something is worth showing, then grows into a compact strip beside the camera or, on hover, into a card underneath it.

<p align="center"><img src="Resources/AppIcon.icns" width="128" alt="MyNotch icon"></p>

## What it shows

| Module | In the notch |
|---|---|
| **Now playing** | Spotify and Apple Music through their scripting interfaces, plus any other player (Safari, Chrome, IINA…) through an optional system-wide source. Artwork and a level meter beside the housing; transport, scrubber, shuffle/repeat, synced lyrics and your Spotify library heart on the card. |
| **Claude Code** | The five-hour and weekly limits read from the same sign-in the CLI uses, today's tokens, blocks and pace parsed from the local session logs, dollars from `ccusage` when it is installed, and a pulse while Claude works. |
| **Calendar** | A countdown to the next meeting when it is close, popups before it starts, a Join button for Zoom, Meet, Teams and Webex links. |
| **Battery** | Charging and low-battery popups; a gauge with the estimate while it matters. |
| **Pomodoro** | A focus timer: ring beside the housing, controls on the card, a chime between phases. |
| **Shelf** | Drag files onto the notch to keep a copy for a while, then AirDrop them or drag them into another app. |

Every module can be switched off in Settings. A module that is off does nothing at all: no scripts, no processes, no network.

## Install

1. Download `MyNotch-<version>.dmg` from the [latest release](https://github.com/Muhammethasanuyar/myNotch/releases/latest) and drag MyNotch to Applications.
2. Open it once. Current builds are signed **ad hoc**, not with an Apple Developer ID, so macOS will say it could not verify the app. Open **System Settings → Privacy & Security**, scroll to the message about MyNotch and click **Open Anyway**. This is needed once per version.
3. The Setup tab of Settings walks through the optional permissions.

Updates arrive through the app's own **Check for Updates…** menu item (Sparkle, once a day, can be turned off in Settings → General).

Requires macOS 14 Sonoma or later. On a Mac without a notch the surface floats below the menu bar.

## Permissions (all optional)

| Permission | Used for | Asked when |
|---|---|---|
| Automation (Spotify, Music) | Reading what is playing and sending transport commands | The first time a player is running |
| Calendars | The next-meeting countdown | Only when you press *Grant access* in Settings |
| Screen & System Audio Recording | The real-audio level meter | Only when you turn the level meter on |

Nothing is written to the Claude Code sign-in: the token is read from the CLI's own Keychain item and never refreshed, logged or stored anywhere else.

## What leaves this Mac

- **LRCLIB** (`lrclib.net`): artist, title, album and length of the current track, to fetch lyrics — only while lyrics are on.
- **Spotify Web API**: the current track's ID, to read or set the heart — only after you connect your own Spotify app (bring-your-own client ID, PKCE, no client secret).
- **Anthropic** (`api.anthropic.com/api/oauth/usage`): one usage request per poll interval with the Claude Code token.
- **GitHub** (`raw.githubusercontent.com`): the Sparkle appcast, once a day, carrying the app and macOS version.

No analytics, no crash reports.

## Building from source

```bash
brew install xcodegen
scripts/build.sh          # xcodegen generate + xcodebuild (Debug)
scripts/test.sh           # unit tests
scripts/run.sh            # build, relaunch, open
scripts/run.sh --args -openDebugPreview YES   # the Debug Preview window
```

`project.yml` is the single source of truth; `MyNotch.xcodeproj` and `Resources/Info.plist` are generated and not committed. Build products live under `~/Library/Developer/Xcode/DerivedData/MyNotch`. The roadmap, architecture notes and every recorded decision are in `docs/PLAN.md`; the release procedure in `docs/RELEASE.md`.

## Licence

MIT — see [LICENSE](LICENSE). Adapted third-party code and the bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) are listed with their licences in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
