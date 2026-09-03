import SwiftUI

/// A feature that can own the notch. Every integration is a module: it decides how active it is
/// and renders its own compact, expanded and popup views.
///
/// Modules never talk to `NotchViewModel`; they publish through the `EventBus` they receive in
/// `start(context:)` and `ModuleManager` translates that into notch states.
/// Not `Identifiable`: that protocol's `id` requirement is nonisolated and would force every
/// module to spell out `nonisolated let id`, so the id lives here on the main actor instead.
@MainActor
protocol NotchModule: AnyObject {
    /// Stable identifier, also used as `NotchState.expanded(moduleID:)`.
    var id: String { get }
    var displayName: String { get }
    /// Higher wins when two modules report the same activity.
    var priority: Int { get }
    /// Turned off from Settings; a disabled module never wins the notch and its events are dropped.
    var isEnabled: Bool { get set }
    var activity: ModuleActivity { get }

    /// Called once when the module is registered and enabled. Start observers/timers here.
    func start(context: ModuleContext)
    /// Called when the module is disabled or the app shuts down. Stop everything.
    func stop()

    /// Left of the housing in the compact state.
    func compactLeading(namespace: Namespace.ID) -> AnyView
    /// Right of the housing in the compact state.
    func compactTrailing(namespace: Namespace.ID) -> AnyView
    /// The module's full interface, shown below the housing.
    func expandedView(namespace: Namespace.ID) -> AnyView
    /// Popup body; `nil` lets `ModuleManager` fall back to a generic row.
    func popupView(for event: NotchEvent, namespace: Namespace.ID) -> AnyView?
}

extension NotchModule {
    func compactLeading(namespace: Namespace.ID) -> AnyView { AnyView(EmptyView()) }
    func compactTrailing(namespace: Namespace.ID) -> AnyView { AnyView(EmptyView()) }
    func popupView(for event: NotchEvent, namespace: Namespace.ID) -> AnyView? { nil }
}

/// What a module is handed at registration: the bus it announces itself on, and its own id so
/// events do not have to repeat it.
@MainActor
struct ModuleContext {
    let moduleID: String
    private let bus: EventBus

    init(moduleID: String, bus: EventBus) {
        self.moduleID = moduleID
        self.bus = bus
    }

    /// Tell the manager that `activity` changed, so it can re-resolve who owns the notch.
    func activityChanged() {
        bus.post(.activityChanged(moduleID: moduleID))
    }

    /// Ask for a popup. `ModuleManager` decides whether it grows the notch or becomes a banner.
    func post(_ event: NotchEvent) {
        bus.post(.popup(event))
    }

    /// Convenience for modules that only carry a title/detail.
    func post(title: String, detail: String? = nil, symbolName: String? = nil, duration: TimeInterval = 2.5) {
        post(NotchEvent(moduleID: moduleID, title: title, detail: detail, symbolName: symbolName, duration: duration))
    }
}
