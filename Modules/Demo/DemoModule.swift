import SwiftUI

/// Reference implementation of `NotchModule`, used to exercise the compact → expanded → popup
/// triple before the real modules land. It owns fake playback state and is driven manually from
/// the Debug Preview (or by `-debugState` at launch).
///
/// Phase 3 replaces it with the media module; nothing outside `Modules/Demo` depends on it.
@MainActor
@Observable
final class DemoModule: NotchModule {
    let id = "demo"
    let displayName = "Demo"
    let priority = 0

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle
    private(set) var track: DemoTrack = DemoTrack.all[0]
    private(set) var isPlaying = true

    @ObservationIgnored private var context: ModuleContext?
    @ObservationIgnored private var trackIndex = 0

    func start(context: ModuleContext) {
        self.context = context
    }

    func stop() {
        activity = .idle
        context?.activityChanged()
    }

    // MARK: Demo controls

    /// Manual activity control from the Debug Preview.
    func setActivity(_ newActivity: ModuleActivity) {
        guard activity != newActivity else { return }
        activity = newActivity
        context?.activityChanged()
        if newActivity == .urgent {
            context?.post(trackChangeEvent())
        }
    }

    func togglePlayPause() {
        isPlaying.toggle()
    }

    /// Moves to the next fake track: goes live and announces the change with a popup.
    func skipToNextTrack() {
        trackIndex = (trackIndex + 1) % DemoTrack.all.count
        track = DemoTrack.all[trackIndex]
        isPlaying = true
        if activity == .idle {
            activity = .live
            context?.activityChanged()
        }
        context?.post(trackChangeEvent())
    }

    private func trackChangeEvent() -> NotchEvent {
        NotchEvent(
            moduleID: id,
            title: "Now playing",
            detail: "\(track.artist) — \(track.title)",
            symbolName: "music.note",
            duration: 2.5
        )
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(DemoCompactLeading(module: self, namespace: namespace))
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(DemoCompactTrailing(module: self))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(DemoExpandedView(module: self, namespace: namespace))
    }

    func popupView(for event: NotchEvent, namespace: Namespace.ID) -> AnyView? {
        AnyView(DemoPopupView(module: self, event: event))
    }
}

/// Fake now-playing item: title, artist and the two colours its artwork is built from.
nonisolated struct DemoTrack: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let startColor: Color
    let endColor: Color

    static let all: [DemoTrack] = [
        DemoTrack(id: "say-it-aint-so", title: "Say It Ain't So", artist: "Weezer", startColor: .orange, endColor: .purple),
        DemoTrack(id: "blue-monday", title: "Blue Monday", artist: "New Order", startColor: .blue, endColor: .cyan),
        DemoTrack(id: "teardrop", title: "Teardrop", artist: "Massive Attack", startColor: .pink, endColor: .indigo)
    ]
}
