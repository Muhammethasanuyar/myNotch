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
    @Environment(\.wingContentSize) private var size

    var body: some View {
        DemoArtwork(track: module.track, cornerRadius: size * 0.25)
            .matchedGeometryEffect(id: DemoModule.artworkID, in: namespace)
            .frame(width: size, height: size)
    }
}

/// Compact trailing wing: four bars that wiggle while playing and rest when paused.
struct DemoCompactTrailing: View {
    let module: DemoModule
    @Environment(\.wingContentSize) private var size

    var body: some View {
        EqualizerBars(isPlaying: module.isPlaying, barWidth: size / 10)
            .frame(width: size, height: size * 0.7)
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
        // The wings show the demo artwork and meter; the strip carries the line, like every module.
        NotchPopupLine(title: event.title, detail: event.detail)
    }
}


extension DemoModule {
    /// Shared id for the artwork that morphs between compact and expanded.
    static let artworkID = "demo.artwork"
}
