# Changelog

All notable changes to MyNotch are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/) with a `0.x` major while the app is young. `scripts/release.sh` takes a release's notes from its section below.

## [Unreleased]

## [0.2.0] - 2026-09-07

### Added
- Volume: a short popup whenever the output level or mute changes, and an optional mode (Settings → Sound) that takes the volume keys before macOS does so the system HUD stays away — needs the Accessibility permission; brightness keys are never touched.
- Output device: a popup when AirPods, headphones or a display take over the sound, with the AirPods battery when the system reports it; a card with transport and latency.
- Downloads (off by default): Safari and Chromium downloads as a progress ring beside the housing, a popup when a file lands, and a card that can put the file on the shelf. Asks for the Downloads folder permission only when turned on.
- Builds (off by default): finished Xcode builds from DerivedData and GitHub Actions runs through your own `gh` — no token stored — as popups, with the last few on the card.
- Now playing: shuffle and repeat for players followed through the system-wide source; a six-band level meter on the player card.
- Claude Code: when Anthropic cannot be reached, a limit Claude Code itself hit stands in on the ring (dashed) until it resets, and hitting a limit posts one popup.
- Settings → Media links straight to the Screen & System Audio Recording privacy pane when the level meter hears nothing.

### Changed
- A scheduled update check that finds a new version now turns the menu bar item into "Update to x.y.z available…" instead of waiting for a window the app never shows; the standard Sparkle window opens when you ask.
- The adapter health check reruns only when macOS or the bundled adapter changes, not on every version bump.
- The Spotify token file is created owner-only and swapped into place; a corrupt file shows as an error in Settings instead of a silent disconnect.

## [0.1.1] - 2026-09-07

### Changed
- No functional changes: this release exercises the update channel end to end (appcast, EdDSA signature, in-app install) from 0.1.0.

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
