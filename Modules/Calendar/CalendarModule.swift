import AppKit
import SwiftUI

/// The next meeting in the notch: a countdown beside the housing when it is close, popups five
/// minutes before and at the start, and a rail of the next events with a Join button when opened.
@MainActor
@Observable
final class CalendarModule: NotchModule {
    let id = "calendar"
    let displayName = L("module.calendar", "Calendar")
    /// Above Claude and the battery, below music: a countdown matters more than a percentage,
    /// but the five-minute popup already interrupts a song.
    let priority = 7

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle
    var alertsEnabled = true

    let service: CalendarService
    @ObservationIgnored private var context: ModuleContext?
    @ObservationIgnored private var announced: Set<String> = []

    /// Offered once the user granted access; the Calendar app's icon marks it in the switcher.
    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "calendar", appBundleIdentifier: "com.apple.iCal", isAvailable: service.hasAccess)]
    }

    init(service: CalendarService = CalendarService()) {
        self.service = service
    }

    func start(context: ModuleContext) {
        self.context = context
        service.onChange = { [weak self] in self?.evaluate() }
        service.start()
        evaluate()
    }

    func stop() {
        service.onChange = nil
        service.stop()
        activity = .idle
        context?.activityChanged()
    }

    private func evaluate() {
        let now = Date()
        let next = CalendarRules.activity(next: service.next, now: now, leadMinutes: service.leadMinutes)
        if next != activity {
            activity = next
            context?.activityChanged()
        }
        let result = CalendarRules.alerts(events: service.events, now: now, announced: announced)
        announced = result.announced
        guard alertsEnabled else { return }
        for (event, kind) in result.alerts {
            context?.post(CalendarRules.popupEvent(for: event, kind: kind, moduleID: id))
        }
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(CalendarCompactLeading(service: service))
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(CalendarCompactTrailing(service: service))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(CalendarExpandedView(service: service))
    }
}
