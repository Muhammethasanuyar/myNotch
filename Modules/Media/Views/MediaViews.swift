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
        if controller.permission == .denied {
            MediaPermissionView()
        } else if let state = controller.state {
            player(for: state)
        } else {
            MediaIdleView()
        }
    }

    private func player(for state: MediaState) -> some View {
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

                Spacer(minLength: 4)
                MediaScrubber(state: state, accent: controller.artwork?.accent ?? .white) { position in
                    controller.send(.seek(position))
                }

                HStack(spacing: 24) {
                    transportButton("backward.fill") { controller.send(.previous) }
                    transportButton(state.isPlaying ? "pause.fill" : "play.fill") {
                        controller.applyOptimisticPlayPause()
                        controller.send(.playPause)
                    }
                    transportButton("forward.fill") { controller.send(.next) }
                }
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
        .foregroundStyle(.white)
    }

    /// A drag gesture rather than a tap: inside a non-activating panel the first tap is otherwise
    /// swallowed as the window-activation click.
    private func transportButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let inside = abs(value.translation.width) < 20 && abs(value.translation.height) < 20
                if inside { action() }
            })
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
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.title2)
            Text("Nothing playing")
                .font(.headline)
            Text("Start Spotify or Music")
                .font(.caption)
                .foregroundStyle(.secondary)
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
