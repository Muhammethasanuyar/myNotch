# Changelog

All notable changes to MyNotch are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/) with a `0.x` major while the app is young. `scripts/release.sh` takes a release's notes from its section below.

## [Unreleased]

## [0.1.0] - 2026-09-07

### Added
- The notch engine: closed, compact, expanded and popup states drawn over the housing (or floating below the menu bar on a Mac without one), hover to open with a grace zone, click-through everywhere the surface is not drawn, drag a file onto the housing to open the shelf.
- Now playing for Spotify and Apple Music: artwork and a level meter beside the housing; transport, scrubber, shuffle and repeat, synced lyrics (LRCLIB) and the Spotify library heart (Web API, bring-your-own client ID) on the card. An optional system-wide source through the bundled mediaremote-adapter covers Safari, Chrome and other players; an optional real-audio level meter through a Core Audio process tap.
- Claude Code usage: the five-hour and weekly limits from the CLI's own sign-in (read only), today's tokens, blocks and pace parsed from the local session logs, dollars from `ccusage` when installed, a pulse while Claude works, threshold popups.
- Calendar: countdown to the next meeting, popups before it starts, a Join button for Zoom, Meet, Teams and Webex links.
- Battery: charging and low-battery popups, a gauge with the estimate.
- Pomodoro: focus timer with a ring beside the housing, controls on the card and a chime between phases; survives a relaunch.
- Shelf: files dropped on the notch are copied and kept for a while, then AirDropped or dragged into another app.
- Settings window with one pane per module, a Setup checklist for permissions and sign-ins, launch at login, display selection, English and Turkish.
- Updates through Sparkle, offered once a day and never installed unasked.
