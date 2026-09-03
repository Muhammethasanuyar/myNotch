import Foundation

/// A transient announcement shown as a popup, or as a banner while the notch is expanded.
/// Phase 1 carries only what the engine needs; Phase 2 adds module priorities and the EventBus.
nonisolated struct NotchEvent: Equatable, Sendable, Identifiable {
    let id: UUID
    let moduleID: String
    let title: String
    let detail: String?
    /// SF Symbol shown next to the title.
    let symbolName: String?
    /// How long the popup stays before the notch returns to its resting state.
    let duration: TimeInterval

    init(
        moduleID: String,
        title: String,
        detail: String? = nil,
        symbolName: String? = nil,
        duration: TimeInterval = 2.5,
        id: UUID = UUID()
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.duration = duration
    }
}
