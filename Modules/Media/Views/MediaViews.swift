import SwiftUI

/// Artwork, or a neutral placeholder while it loads.
struct MediaArtworkView: View {
    let artwork: MediaArtwork?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay {
                if let image = artwork?.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: cornerRadius * 1.4))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Compact leading wing: the artwork, tagged so it travels into the expanded card.
struct MediaCompactLeading: View {
    let controller: MediaController
    let namespace: Namespace.ID

    var body: some View {
        MediaArtworkView(artwork: controller.artwork, cornerRadius: 5)
            .matchedGeometryEffect(id: MediaModule.artworkID, in: namespace)
            .frame(width: 20, height: 20)
    }
}

/// Compact trailing wing: the level meter, tinted with the artwork's accent.
struct MediaCompactTrailing: View {
    let controller: MediaController

    var body: some View {
        EqualizerBars(
            isPlaying: controller.state?.isPlaying ?? false,
            color: controller.artwork?.accent ?? .white
        )
        .frame(width: 20, height: 14)
    }
}

/// The module's full interface: artwork, titles, a draggable scrubber and transport controls.
struct MediaExpandedView: View {
    let controller: MediaController
    let namespace: Namespace.ID

    var body: some View {
        Group {
            if controller.permission == .denied {
                MediaPermissionView()
            } else if let state = controller.state {
                player(for: state)
            } else {
                MediaIdleView(playerName: controller.displayProvider?.displayName)
            }
        }
        // While the player is on screen the controller re-anchors the playhead every couple of
        // seconds, so a seek made inside Spotify (which it never announces) cannot leave the
        // scrubber and the lyrics behind.
        .onAppear { controller.setDetailVisible(true) }
        .onDisappear { controller.setDetailVisible(false) }
    }

    private func player(for state: MediaState) -> some View {
        VStack(spacing: 8) {
            details(for: state)
            MediaControlBar(controller: controller, state: state)
        }
        .foregroundStyle(.white)
    }

    private func details(for state: MediaState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MediaArtworkView(artwork: controller.artwork, cornerRadius: 12)
                .matchedGeometryEffect(id: MediaModule.artworkID, in: namespace)
                .frame(width: 90, height: 90)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: controller.activeProvider?.symbolName ?? "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(state.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                MediaLyricsView(state: state, service: controller.lyrics, accent: controller.artwork?.accent ?? .white)
                    .frame(height: MediaLyricsView.bandHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                Spacer(minLength: 0)

                MediaScrubber(state: state, accent: controller.artwork?.accent ?? .white) { position in
                    controller.send(.seek(position))
                }
            }
        }
    }
}

/// The player's controls, laid out like a music app's: shuffle, previous, a filled play/pause
/// circle, next and repeat, centred across the whole card, with the favourite button on the left.
struct MediaControlBar: View {
    let controller: MediaController
    let state: MediaState

    private var accent: Color { controller.artwork?.accent ?? .white }

    /// A control the player will not accept still shows its real state, just muted, because seeing
    /// that shuffle is on is useful even when we cannot turn it off from here.
    private func tint(isOn: Bool, isEnabled: Bool) -> Color {
        if isOn { return isEnabled ? accent : accent.opacity(0.45) }
        return .white.opacity(isEnabled ? 0.75 : 0.25)
    }

    private func unsupported(_ what: String) -> String {
        "\(state.providerName) does not let other apps control \(what)"
    }

    var body: some View {
        let capabilities = controller.capabilities
        // A ZStack rather than an HStack with spacers: the transport stays centred in the card no
        // matter how wide the favourite button beside it is.
        ZStack {
            HStack(spacing: 20) {
                MediaControlButton(
                    symbol: "shuffle",
                    size: 12,
                    tint: tint(isOn: state.isShuffling, isEnabled: capabilities.canShuffle),
                    isEnabled: capabilities.canShuffle
                ) { controller.toggleShuffle() }
                .help(capabilities.canShuffle ? "Shuffle" : unsupported("shuffle"))

                MediaControlButton(symbol: "backward.end.fill", size: 15) { controller.send(.previous) }

                playPauseButton

                MediaControlButton(symbol: "forward.end.fill", size: 15) { controller.send(.next) }

                MediaControlButton(
                    symbol: state.repeatMode.symbolName,
                    size: 12,
                    tint: tint(isOn: state.repeatMode.isOn, isEnabled: capabilities.canRepeat),
                    isEnabled: capabilities.canRepeat
                ) { controller.cycleRepeat() }
                .help(capabilities.canRepeat ? "Repeat" : unsupported("repeat"))
            }

            HStack {
                favoriteButton
                Spacer(minLength: 0)
            }
        }
        .frame(height: 30)
    }

    private var playPauseButton: some View {
        MediaControlButton(
            symbol: state.isPlaying ? "pause.fill" : "play.fill",
            size: 12,
            tint: .black,
            background: .white,
            diameter: 28
        ) { controller.togglePlayPause() }
    }

    /// What the heart shows for the active player. Until a player can save tracks the heart stays
    /// dimmed but clickable: the tap starts whatever makes it work and the tooltip says what that is.
    private var favoriteAppearance: (symbol: String, hint: String, tint: Color, isClickable: Bool) {
        switch controller.favoriteSupport {
        case .available:
            return (state.isFavorite ? "heart.fill" : "heart",
                    state.isFavorite ? "Remove from favourites" : "Add to favourites",
                    tint(isOn: state.isFavorite, isEnabled: true),
                    true)
        case .needsConnection(let hint), .needsSetup(let hint):
            return ("heart", hint, tint(isOn: false, isEnabled: false), true)
        case .unsupported(let reason):
            return ("heart", reason, tint(isOn: false, isEnabled: false), false)
        }
    }

    private var favoriteButton: some View {
        let appearance = favoriteAppearance
        return MediaControlButton(
            symbol: appearance.symbol,
            size: 13,
            tint: appearance.tint,
            isEnabled: appearance.isClickable
        ) { controller.toggleFavorite() }
        .help(appearance.hint)
    }
}

/// One control. Taps go through `notchTap`, because a plain tap inside a non-activating panel is
/// swallowed as the window-activation click.
struct MediaControlButton: View {
    let symbol: String
    var size: CGFloat = 15
    var tint: Color = .white
    var background: Color?
    var diameter: CGFloat = 26
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            if let background {
                Circle()
                    .fill(background)
                    .frame(width: diameter, height: diameter)
            }
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isHovering && isEnabled ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .notchTap(isEnabled: isEnabled, perform: action)
        .allowsHitTesting(isEnabled)
    }
}

/// Progress line that can be dragged to seek. Repaints twice a second while playing; it only
/// exists while the notch is expanded, so nothing ticks when the surface is closed.
struct MediaScrubber: View {
    let state: MediaState
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @State private var dragProgress: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: state.isPlaying ? 0.5 : 3600)) { context in
            let progress = dragProgress ?? state.progress(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(accent)
                            .frame(width: max(0, geometry.size.width * progress))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragProgress = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                            }
                            .onEnded { value in
                                let ratio = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                                dragProgress = nil
                                if let duration = state.duration {
                                    onSeek(ratio * duration)
                                }
                            }
                    )
                }
                .frame(height: 4)

                HStack {
                    Text(Self.time(state.duration.map { $0 * progress } ?? 0))
                    Spacer(minLength: 0)
                    Text(Self.time(state.duration ?? 0))
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }

    nonisolated static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Track-change popup: artwork plus title and artist.
struct MediaPopupView: View {
    let controller: MediaController
    let event: NotchEvent

    var body: some View {
        HStack(spacing: 10) {
            MediaArtworkView(artwork: controller.artwork, cornerRadius: 6)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.bold())
                    .lineLimit(1)
                if let detail = event.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

/// Shown when Automation has not been granted, so the module never fails silently.
struct MediaPermissionView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.title2)
            Text("Automation permission needed")
                .font(.headline)
            Text("System Settings → Privacy & Security → Automation → MyNotch")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

/// Nothing is playing, but the user expanded the notch anyway.
struct MediaIdleView: View {
    /// The player the card is showing, when the user picked one that has nothing loaded.
    var playerName: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.title2)
            Text(playerName.map { "Nothing playing in \($0)" } ?? "Nothing playing")
                .font(.headline)
            if playerName == nil {
                Text("Start Spotify or Music")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

/// Placeholder visualizer: animated while playing, flat when paused. Phase 6 may swap in a real
/// audio meter; the shape of this view stays the same.
struct EqualizerBars: View {
    let isPlaying: Bool
    var color: Color = .white
    var barCount = 4

    var body: some View {
        if isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at time: Double?) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: height(at: time, phase: Double(index) * 1.1), anchor: .center)
            }
        }
    }

    /// Two summed sines give an organic, non-repeating wiggle; paused rests low and flat.
    private func height(at time: Double?, phase: Double) -> CGFloat {
        guard let time else { return 0.2 }
        let a = sin(time * 5.2 + phase) * 0.5 + 0.5
        let b = sin(time * 9.7 + phase * 2.1) * 0.5 + 0.5
        return CGFloat(0.25 + (a * 0.6 + b * 0.4) * 0.75)
    }
}

/// Synced lyrics that advance with the track, the way a player's lyrics strip does: the line being
/// sung sits at the top in the artwork's accent colour, the next one waits below it dimmed, and the
/// stack slides up as the song moves on.
///
/// It exists only while the notch is expanded and ticks at 4 Hz only while playing, so a closed or
/// paused notch costs nothing.
struct MediaLyricsView: View {
    let state: MediaState
    let service: LyricsService
    let accent: Color

    /// Height of one line; two of them fit the gap above the scrubber.
    static let rowHeight: CGFloat = 17
    /// The band the lyrics live in. Fixed, so lines entering and leaving during a transition
    /// cannot resize it or spill into the title above and the scrubber below.
    static let bandHeight: CGFloat = rowHeight * 2

    var body: some View {
        switch service.status {
        case .loaded(let lyrics) where !lyrics.isEmpty:
            // Driven by the exact line-change instants, so a line never appears a tick late.
            TimelineView(.explicit(schedule(for: lyrics))) { context in
                scroller(lyrics: lyrics, at: state.liveElapsed(at: context.date) + LyricsService.lead)
            }
        case .loading:
            Text("Lyrics…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .idle, .unavailable, .loaded:
            // Nothing for this track: leave the gap empty rather than apologising for it.
            Color.clear
        }
    }

    /// While playing, wake exactly when the next lines start; while paused, render once.
    private func schedule(for lyrics: Lyrics) -> [Date] {
        let now = Date()
        guard state.isPlaying else { return [now] }
        return LyricsParser.boundaries(
            lines: lyrics.lines,
            anchor: state.elapsedAt,
            elapsed: state.elapsed,
            lead: LyricsService.lead,
            after: now
        )
    }

    private func scroller(lyrics: Lyrics, at elapsed: TimeInterval) -> some View {
        // Before the first timestamp the intro is still running, so nothing is highlighted yet.
        let active = LyricsParser.index(at: elapsed, in: lyrics.lines) ?? -1
        return ZStack(alignment: .topLeading) {
            ForEach(window(around: active, count: lyrics.lines.count), id: \.self) { index in
                line(lyrics.lines[index].text, distance: index - active, isSynced: lyrics.isSynced)
                    .offset(y: CGFloat(index - active) * Self.rowHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.bandHeight, alignment: .top)
        .clipped()
        .animation(.easeOut(duration: 0.32), value: active)
    }

    private func line(_ text: String, distance: Int, isSynced: Bool) -> some View {
        Text(text)
            .font(.system(size: distance == 0 ? 12 : 11, weight: distance == 0 ? .semibold : .regular))
            // Unsynced text keeps the accent for itself: white says "roughly here", not "exactly now".
            .foregroundStyle(distance == 0
                             ? AnyShapeStyle(isSynced ? accent : Color.white.opacity(0.85))
                             : AnyShapeStyle(Color.white.opacity(0.35)))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: Self.rowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The line that just finished fades as it leaves the top of the window.
            .opacity(distance < 0 ? 0 : 1)
    }

    /// Only the lines around the current one are rendered; a 300-line LRC file must not become
    /// 300 views.
    private func window(around active: Int, count: Int) -> [Int] {
        let lower = max(0, active - 1)
        let upper = min(count - 1, max(active, 0) + 2)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }
}
