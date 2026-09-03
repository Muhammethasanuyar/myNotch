import SwiftUI

/// Album artwork stand-in: the track's two colours in a rounded gradient.
struct DemoArtwork: View {
    let track: DemoTrack
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [track.startColor, track.endColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

/// Compact leading wing: the artwork, tagged so it travels into the expanded card.
struct DemoCompactLeading: View {
    let module: DemoModule
    let namespace: Namespace.ID

    var body: some View {
        DemoArtwork(track: module.track, cornerRadius: 5)
            .matchedGeometryEffect(id: DemoModule.artworkID, in: namespace)
            .frame(width: 20, height: 20)
    }
}

/// Compact trailing wing: four bars that wiggle while playing and rest when paused.
struct DemoCompactTrailing: View {
    let module: DemoModule

    var body: some View {
        DemoBars(isPlaying: module.isPlaying)
            .frame(width: 20, height: 14)
    }
}

/// The module's full interface below the housing.
struct DemoExpandedView: View {
    let module: DemoModule
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DemoArtwork(track: module.track, cornerRadius: 12)
                .matchedGeometryEffect(id: DemoModule.artworkID, in: namespace)
                .frame(width: 90, height: 90)
            VStack(alignment: .leading, spacing: 4) {
                Text(module.track.title)
                    .font(.headline)
                Text(module.track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 22) {
                    Image(systemName: "backward.fill")
                    Image(systemName: module.isPlaying ? "pause.fill" : "play.fill")
                    Image(systemName: "forward.fill")
                }
                .font(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

/// Popup body: artwork plus the event text, so a track change reads at a glance.
struct DemoPopupView: View {
    let module: DemoModule
    let event: NotchEvent

    var body: some View {
        HStack(spacing: 10) {
            DemoArtwork(track: module.track, cornerRadius: 6)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.bold())
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

/// Placeholder visualizer: a 24 fps timeline while playing, flat bars when paused.
/// Phase 6 may replace it with a real audio meter.
private struct DemoBars: View {
    let isPlaying: Bool

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
            ForEach(0..<4, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: height(at: time, phase: Double(index) * 1.1), anchor: .center)
            }
        }
    }

    private func height(at time: Double?, phase: Double) -> CGFloat {
        guard let time else { return 0.2 }
        let a = sin(time * 5.2 + phase) * 0.5 + 0.5
        let b = sin(time * 9.7 + phase * 2.1) * 0.5 + 0.5
        return CGFloat(0.25 + (a * 0.6 + b * 0.4) * 0.75)
    }
}

extension DemoModule {
    /// Shared id for the artwork that morphs between compact and expanded.
    static let artworkID = "demo.artwork"
}
