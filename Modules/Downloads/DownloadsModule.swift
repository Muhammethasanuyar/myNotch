import SwiftUI

/// Browser downloads in the notch: a progress ring beside the housing while a file arrives, a
/// popup when it is done, and a card that lists what is coming and what just came — with a way to
/// put a finished file on the shelf. Ships off: watching the folder needs a permission.
@MainActor
@Observable
final class DownloadsModule: NotchModule {
    let id = "downloads"
    let displayName = L("module.downloads", "Downloads")
    /// Transient: below music, meetings, the timer and the battery — but on the strip when nothing else is.
    let priority = 3

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle
    var completionPopups = true

    let service: DownloadsService
    @ObservationIgnored private var context: ModuleContext?
    @ObservationIgnored private var liveTask: Task<Void, Never>?

    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "arrow.down.circle.fill", isAvailable: !service.items.isEmpty)]
    }

    /// Whether the card can offer "put on the shelf".
    var canOfferFiles: Bool { context?.canOfferFiles ?? false }

    init(service: DownloadsService = DownloadsService()) {
        self.service = service
    }

    func start(context: ModuleContext) {
        self.context = context
        service.onChange = { [weak self] in self?.updateActivity() }
        service.onCompleted = { [weak self] item in
            guard let self, completionPopups else { return }
            self.context?.post(DownloadsRules.completionEvent(item, moduleID: id))
        }
        service.start()
    }

    func stop() {
        liveTask?.cancel()
        liveTask = nil
        service.onChange = nil
        service.onCompleted = nil
        service.stop()
        activity = .idle
        context?.activityChanged()
    }

    /// Hands a finished file to the shelf.
    func offerToShelf(_ item: DownloadItem) {
        guard item.isFinished else { return }
        context?.offerFiles([item.destination])
    }

    private func updateActivity() {
        let now = Date()
        let next = DownloadsRules.activity(service.items, now: now)
        if next != activity {
            activity = next
            context?.activityChanged()
        }
        liveTask?.cancel()
        liveTask = nil
        if next == .live, let until = DownloadsRules.liveUntil(service.items, now: now) {
            liveTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0.1, until.timeIntervalSince(now))))
                guard !Task.isCancelled else { return }
                self?.updateActivity()
            }
        }
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(DownloadsCompactLeading(service: service))
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(DownloadsCompactTrailing(service: service))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(DownloadsExpandedView(module: self))
    }
}
