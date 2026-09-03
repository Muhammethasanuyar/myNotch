import SwiftUI

/// Stand-in content for the engine until Phase 2 delivers real modules. Shaped like the media
/// module so the compact → expanded artwork morph can be tuned on real proportions.
enum FakeNotchContent {
    static let moduleID = "debug"

    static func sampleEvent(duration: TimeInterval = 2.5) -> NotchEvent {
        NotchEvent(
            moduleID: moduleID,
            title: "Now playing",
            detail: "Weezer — Say It Ain't So",
            symbolName: "music.note",
            duration: duration
        )
    }

    static func provider() -> NotchContentProvider {
        NotchContentProvider(
            compactLeading: { namespace in
                AnyView(
                    FakeArtwork(cornerRadius: 5)
                        .matchedGeometryEffect(id: "artwork", in: namespace)
                        .frame(width: 20, height: 20)
                )
            },
            compactTrailing: { _ in
                AnyView(FakeBars().frame(width: 20, height: 14))
            },
            expanded: { _, namespace in
                AnyView(FakeExpandedCard(namespace: namespace))
            },
            popup: { event, _ in
                AnyView(FakePopupRow(event: event))
            }
        )
    }
}

private struct FakeArtwork: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// Four bars wiggling on a 24 fps timeline. Lives only while the compact state is on screen.
private struct FakeBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.white)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: height(at: t, phase: Double(index) * 1.1), anchor: .center)
                }
            }
        }
    }

    private func height(at t: Double, phase: Double) -> CGFloat {
        let a = sin(t * 5.2 + phase) * 0.5 + 0.5
        let b = sin(t * 9.7 + phase * 2.1) * 0.5 + 0.5
        return CGFloat(0.25 + (a * 0.6 + b * 0.4) * 0.75)
    }
}

private struct FakeExpandedCard: View {
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FakeArtwork(cornerRadius: 12)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .frame(width: 90, height: 90)
            VStack(alignment: .leading, spacing: 4) {
                Text("Say It Ain't So")
                    .font(.headline)
                Text("Weezer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 22) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "play.fill")
                    Image(systemName: "forward.fill")
                }
                .font(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

private struct FakePopupRow: View {
    let event: NotchEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.symbolName ?? "bell.fill")
                .font(.title3)
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
