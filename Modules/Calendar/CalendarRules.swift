import Foundation

/// Pure decisions of the calendar module: which events count, when the module is live, when the
/// next thing happens and what the popups say.
nonisolated enum CalendarRules {
    static let maxVisible = 3
    /// Hosts whose links open a meeting; anything else stays a plain URL.
    static let meetingHosts: [(suffix: String, provider: MeetingProvider)] = [
        ("zoom.us", .zoom), ("meet.google.com", .meet), ("teams.microsoft.com", .teams), ("teams.live.com", .teams), ("webex.com", .webex)
    ]

    // MARK: Links

    /// The first meeting link among the event's URL, location and notes.
    static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        var candidates: [URL] = []
        if let url { candidates.append(url) }
        candidates += urls(in: location) + urls(in: notes)
        return candidates.first { provider(for: $0) != nil }
    }

    static func provider(for url: URL) -> MeetingProvider? {
        guard let host = url.host?.lowercased() else { return nil }
        return meetingHosts.first { host == $0.suffix || host.hasSuffix("." + $0.suffix) }?.provider
    }

    private static func urls(in text: String?) -> [URL] {
        guard let text, !text.isEmpty else { return [] }
        var found: [URL] = []
        for raw in text.split(whereSeparator: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "\"" || $0 == "'" || $0 == ")" || $0 == "(" || $0 == "," }) {
            let piece = String(raw)
            guard piece.hasPrefix("http://") || piece.hasPrefix("https://"), let url = URL(string: piece) else { continue }
            found.append(url)
        }
        return found
    }

    // MARK: Selection

    /// The next few events worth showing: not over, not all-day, not declined, from the chosen
    /// calendars (none chosen = all), soonest first.
    static func visible(_ events: [CalendarEvent], selectedCalendarIDs: Set<String>, now: Date) -> [CalendarEvent] {
        events
            .filter { $0.end > now && !$0.isAllDay && !$0.isDeclined && (selectedCalendarIDs.isEmpty || selectedCalendarIDs.contains($0.calendarID)) }
            .sorted { $0.start < $1.start }
            .prefix(maxVisible)
            .map { $0 }
    }

    /// Live only when the next meeting is close or under way; the strip is not a calendar.
    static func activity(next: CalendarEvent?, now: Date, leadMinutes: Int) -> ModuleActivity {
        guard let next, next.end > now, next.start.timeIntervalSince(now) <= TimeInterval(leadMinutes) * 60 else { return .idle }
        return .live
    }

    /// Moments the module has to wake for: the lead, the five-minute warning, the start, the end.
    static func boundaries(for event: CalendarEvent, leadMinutes: Int) -> [Date] {
        [event.start.addingTimeInterval(-TimeInterval(leadMinutes) * 60), event.start.addingTimeInterval(-300), event.start, event.end]
    }

    static func nextBoundary(events: [CalendarEvent], now: Date, leadMinutes: Int) -> Date? {
        events.flatMap { boundaries(for: $0, leadMinutes: leadMinutes) }.filter { $0 > now }.min()
    }

    /// One popup per event per boundary, whichever refresh happens to land in the window.
    static func alerts(events: [CalendarEvent], now: Date, announced: Set<String>) -> (alerts: [(CalendarEvent, CalendarAlertKind)], announced: Set<String>) {
        var announced = announced
        var alerts: [(CalendarEvent, CalendarAlertKind)] = []
        for event in events where event.end > now {
            let untilStart = event.start.timeIntervalSince(now)
            if untilStart <= 300, untilStart > 60, !announced.contains(event.id + "|5") {
                announced.insert(event.id + "|5")
                alerts.append((event, .fiveMinutes))
            }
            if untilStart <= 0, untilStart > -120, !announced.contains(event.id + "|0") {
                announced.insert(event.id + "|0")
                announced.insert(event.id + "|5")
                alerts.append((event, .starting))
            }
        }
        return (alerts, announced)
    }

    // MARK: Text

    /// "12m" until the start, "now" once it has begun.
    static func countdownText(to start: Date, now: Date, bundle: Bundle = .main, locale: Locale = .current) -> String {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return String(localized: "calendar.now", defaultValue: "now", bundle: bundle) }
        let minutes = Int((seconds / 60).rounded(.up))
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(minutes * 60).formatted(.units(allowed: allowed, width: .narrow, maximumUnitCount: 2).locale(locale))
    }

    static func timeRange(_ event: CalendarEvent) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return event.start.formatted(style) + "–" + event.end.formatted(style)
    }

    static func popupEvent(for event: CalendarEvent, kind: CalendarAlertKind, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        let detail = [event.calendarTitle, event.provider.map { providerName($0, bundle: bundle) }].compactMap { $0 }.joined(separator: " · ")
        switch kind {
        case .fiveMinutes:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "calendar.event.fiveMinutes", defaultValue: "\(event.title) in 5 minutes", bundle: bundle),
                              detail: detail, symbolName: "calendar.badge.clock", duration: 4)
        case .starting:
            return NotchEvent(moduleID: moduleID,
                              title: String(localized: "calendar.event.starting", defaultValue: "\(event.title) is starting", bundle: bundle),
                              detail: detail, symbolName: event.joinURL == nil ? "calendar" : "video.fill", duration: 6)
        }
    }

    static func providerName(_ provider: MeetingProvider, bundle: Bundle = .main) -> String {
        switch provider {
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .teams: return "Teams"
        case .webex: return "Webex"
        case .other: return String(localized: "calendar.provider.other", defaultValue: "Video call", bundle: bundle)
        }
    }

    static func symbol(for provider: MeetingProvider?) -> String {
        provider == nil ? "calendar.badge.clock" : "video.fill"
    }

    // MARK: Explanations

    static func railExplanation(count: Int, hours: Int, bundle: Bundle = .main) -> String {
        String(localized: "calendar.explain.rail", defaultValue: "The next \(count) events on a \(hours)-hour rail, drawn in their calendars' colours; the marker is now.", bundle: bundle)
    }

    static func nextExplanation(_ event: CalendarEvent, now: Date, bundle: Bundle = .main) -> String {
        if event.start <= now {
            return String(localized: "calendar.explain.underway", defaultValue: "Under way since \(event.start.formatted(date: .omitted, time: .shortened)); ends \(event.end.formatted(date: .omitted, time: .shortened)).", bundle: bundle)
        }
        return String(localized: "calendar.explain.next", defaultValue: "Starts in \(countdownText(to: event.start, now: now, bundle: bundle)). A popup comes five minutes before and at the start.", bundle: bundle)
    }

    static func joinExplanation(_ provider: MeetingProvider, bundle: Bundle = .main) -> String {
        String(localized: "calendar.explain.join", defaultValue: "Opens the \(providerName(provider, bundle: bundle)) link from the invitation in your browser or app.", bundle: bundle)
    }
}
