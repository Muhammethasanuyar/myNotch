import AppKit
import EventKit
import Observation

/// Reads upcoming events once access has been granted, and again only when the calendar database
/// changes, the Mac wakes, the day turns, or the next event boundary arrives. No polling.
@MainActor
@Observable
final class CalendarService {
    private(set) var access: CalendarAccess
    private(set) var events: [CalendarEvent] = []
    /// Every calendar the store knows, for the settings pane's selection.
    private(set) var calendars: [(id: String, title: String, color: CalendarColor)] = []

    var leadMinutes = 15 {
        didSet { if leadMinutes != oldValue { refresh() } }
    }
    var selectedCalendarIDs: Set<String> = [] {
        didSet { if selectedCalendarIDs != oldValue { refresh() } }
    }

    /// Called after every refresh, with the events already filtered and ordered.
    var onChange: (() -> Void)?

    private let store = EKEventStore()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    init() {
        access = CalendarAccess(status: EKEventStore.authorizationStatus(for: .event))
    }

    var hasAccess: Bool { access == .authorized }

    var next: CalendarEvent? { events.first }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        ]
        refresh()
    }

    func stop() {
        isStarted = false
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        boundaryTask?.cancel()
        boundaryTask = nil
    }

    /// The system prompt, only ever from a button the user pressed.
    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            // The status below says what happened; a denied prompt is not an error worth throwing.
        }
        access = CalendarAccess(status: EKEventStore.authorizationStatus(for: .event))
        refresh()
    }

    // MARK: Reading

    func refresh() {
        access = CalendarAccess(status: EKEventStore.authorizationStatus(for: .event))
        guard access == .authorized else {
            events = []
            calendars = []
            scheduleBoundary()
            onChange?()
            return
        }
        let now = Date()
        let all = store.calendars(for: .event)
        calendars = all.map { ($0.calendarIdentifier, $0.title, Self.color(of: $0)) }.sorted { $0.title < $1.title }
        let chosen = selectedCalendarIDs.isEmpty ? nil : all.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(36 * 3600), calendars: chosen)
        let fetched = store.events(matching: predicate).map(Self.convert)
        events = CalendarRules.visible(fetched, selectedCalendarIDs: selectedCalendarIDs, now: now)
        scheduleBoundary()
        onChange?()
    }

    /// Sleeps until the next moment the picture changes; a lid closing and reopening re-arms it.
    private func scheduleBoundary() {
        boundaryTask?.cancel()
        boundaryTask = nil
        guard let next = CalendarRules.nextBoundary(events: events, now: Date(), leadMinutes: leadMinutes) else { return }
        let delay = max(1, next.timeIntervalSinceNow + 0.5)
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), clock: ContinuousClock())
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        let joinURL = CalendarRules.joinURL(url: event.url, location: event.location, notes: event.notes)
        let declined = event.attendees?.first { $0.isCurrentUser }?.participantStatus == .declined
        return CalendarEvent(
            id: event.eventIdentifier ?? "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            color: color(of: event.calendar),
            joinURL: joinURL,
            provider: joinURL.flatMap(CalendarRules.provider(for:)),
            isDeclined: declined
        )
    }

    private static func color(of calendar: EKCalendar) -> CalendarColor {
        guard let color = calendar.color.usingColorSpace(.sRGB) else { return .fallback }
        return CalendarColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }
}
