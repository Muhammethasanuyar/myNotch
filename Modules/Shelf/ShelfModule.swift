import SwiftUI

/// A shelf for files: drag anything onto the notch and it opens, takes a copy and keeps it for a
/// while; from the card the copies go on to AirDrop, another app or the Trash. The only module
/// that takes drops, so the engine opens it as a file drag arrives.
@MainActor
@Observable
final class ShelfModule: NotchModule {
    let id = "shelf"
    let displayName = L("module.shelf", "Shelf")
    /// Below every ambient module: the shelf only speaks up for two minutes after a drop.
    let priority = 4
    let acceptsDrops = true

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle

    let store: ShelfStore
    @ObservationIgnored private var context: ModuleContext?
    @ObservationIgnored private var liveTask: Task<Void, Never>?

    /// One screen, offered while something is on the shelf.
    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "tray.full.fill", isAvailable: !store.items.isEmpty)]
    }

    init(store: ShelfStore = ShelfStore()) {
        self.store = store
    }

    func start(context: ModuleContext) {
        self.context = context
        store.onChange = { [weak self] in self?.updateActivity() }
        Task { await store.load() }
    }

    func stop() {
        liveTask?.cancel()
        liveTask = nil
        store.onChange = nil
        store.dropHighlight = nil
        activity = .idle
        context?.activityChanged()
    }

    // MARK: Drops

    func dropTargetingChanged(_ unitPoint: CGPoint?) {
        store.dropHighlight = unitPoint.map { ShelfRules.zone(unitPoint: $0) }
    }

    func acceptDrop(_ drop: NotchDrop) -> Bool {
        store.dropHighlight = nil
        if ShelfRules.zone(unitPoint: drop.unitPoint) == .airDrop, ShelfShare.airDrop(drop.urls) {
            context?.post(ShelfRules.airDropEvent(count: drop.urls.count, moduleID: id))
            return true
        }
        Task { [weak self] in
            guard let self else { return }
            let added = await store.accept(drop.urls)
            if added > 0 {
                context?.post(ShelfRules.dropEvent(count: added, moduleID: id))
            }
        }
        return true
    }

    // MARK: Activity

    private func updateActivity() {
        let now = Date()
        let next = ShelfRules.activity(itemCount: store.items.count, lastDropAt: store.lastDropAt, now: now)
        if next != activity {
            activity = next
            context?.activityChanged()
        }
        liveTask?.cancel()
        liveTask = nil
        // Live for a spell after a drop: one wake-up when it ends, no timer.
        if next == .live, let until = ShelfRules.liveUntil(lastDropAt: store.lastDropAt) {
            liveTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSince(now))))
                guard !Task.isCancelled else { return }
                self?.updateActivity()
            }
        }
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(ShelfCompactLeading())
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(ShelfCompactTrailing(store: store))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(ShelfExpandedView(store: store))
    }
}
