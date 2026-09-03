import Foundation

/// What the resolver needs to know about a module. Keeping it a value type makes the priority
/// rules pure and testable without building real modules.
nonisolated struct ModuleSnapshot: Equatable, Sendable {
    let id: String
    let priority: Int
    let activity: ModuleActivity
    let isEnabled: Bool

    init(id: String, priority: Int, activity: ModuleActivity, isEnabled: Bool = true) {
        self.id = id
        self.priority = priority
        self.activity = activity
        self.isEnabled = isEnabled
    }
}

/// Decides which module owns the notch: `urgent > live(priority) > idle`.
nonisolated enum ModuleResolver {
    /// The winning module, or `nil` when every enabled module is idle.
    static func resolve(_ snapshots: [ModuleSnapshot]) -> ModuleSnapshot? {
        snapshots
            .filter { $0.isEnabled && $0.activity > .idle }
            // Highest activity, then highest priority, then id so the result never flickers
            // between two equally ranked modules.
            .max { lhs, rhs in
                if lhs.activity != rhs.activity { return lhs.activity < rhs.activity }
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.id > rhs.id
            }
    }

    /// Whether a popup from `moduleID` may interrupt: the module must exist and be enabled.
    static func acceptsPopup(from moduleID: String, snapshots: [ModuleSnapshot]) -> Bool {
        snapshots.contains { $0.id == moduleID && $0.isEnabled }
    }
}
