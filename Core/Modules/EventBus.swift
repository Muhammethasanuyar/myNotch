import Foundation

/// Fan-out of module announcements to whoever is listening (in practice `ModuleManager`, plus the
/// Debug Preview when it wants to watch traffic).
///
/// Deliberately not Combine: everything here is main-actor UI plumbing, and a plain callback
/// registry keeps Swift 6's `Sendable` requirements out of the module contract.
@MainActor
final class EventBus {
    enum Message: Equatable {
        /// A module wants to interrupt.
        case popup(NotchEvent)
        /// A module's `activity` changed and the notch owner must be re-resolved.
        case activityChanged(moduleID: String)
    }

    /// Keeps a subscription alive. Call `invalidate()` to unsubscribe immediately; releasing the
    /// token unsubscribes too, but only on the next main-actor turn (`deinit` cannot hop synchronously).
    final class Subscription {
        private let token: UUID
        private weak var bus: EventBus?

        fileprivate init(token: UUID, bus: EventBus) {
            self.token = token
            self.bus = bus
        }

        @MainActor
        func invalidate() {
            bus?.removeHandler(token)
            bus = nil
        }

        deinit {
            bus?.scheduleRemoval(of: token)
        }
    }

    private var handlers: [UUID: (Message) -> Void] = [:]

    func subscribe(_ handler: @escaping (Message) -> Void) -> Subscription {
        let token = UUID()
        handlers[token] = handler
        return Subscription(token: token, bus: self)
    }

    func post(_ message: Message) {
        // Snapshot first: a handler may subscribe or unsubscribe while being called.
        for handler in Array(handlers.values) {
            handler(message)
        }
    }

    fileprivate func removeHandler(_ token: UUID) {
        handlers.removeValue(forKey: token)
    }

    /// Called from a released `Subscription`, which runs outside the main actor.
    fileprivate nonisolated func scheduleRemoval(of token: UUID) {
        Task { @MainActor [weak self] in
            self?.removeHandler(token)
        }
    }
}
