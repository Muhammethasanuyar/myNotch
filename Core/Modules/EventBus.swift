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

    /// Cancels its subscription when released, so subscribers only need to hold the token.
    final class Subscription {
        private let cancel: () -> Void
        private var isCancelled = false

        init(cancel: @escaping () -> Void) {
            self.cancel = cancel
        }

        func invalidate() {
            guard !isCancelled else { return }
            isCancelled = true
            cancel()
        }

        deinit {
            if !isCancelled { cancel() }
        }
    }

    private var handlers: [UUID: (Message) -> Void] = [:]

    func subscribe(_ handler: @escaping (Message) -> Void) -> Subscription {
        let token = UUID()
        handlers[token] = handler
        return Subscription { [weak self] in
            self?.handlers.removeValue(forKey: token)
        }
    }

    func post(_ message: Message) {
        // Snapshot first: a handler may subscribe or unsubscribe while being called.
        for handler in handlers.values {
            handler(message)
        }
    }
}
