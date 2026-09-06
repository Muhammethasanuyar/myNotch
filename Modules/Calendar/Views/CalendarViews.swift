import SwiftUI

extension CalendarColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// Compact leading wing: the meeting glyph in the calendar's colour.
struct CalendarCompactLeading: View {
    let service: CalendarService
    @Environment(\.wingContentSize) private var size

    var body: some View {
        if let next = service.next {
            PulsingSymbol(
                systemName: CalendarRules.symbol(for: next.provider),
                pointSize: size * 0.6,
                weight: .bold,
                color: next.color.color,
                isActive: next.start <= Date()
            )
        }
    }
}

/// Compact trailing wing: minutes to the start, re-read on each minute boundary while on screen.
struct CalendarCompactTrailing: View {
    let service: CalendarService
    @Environment(\.wingContentSize) private var size

    var body: some View {
        if let next = service.next {
            TimelineView(.periodic(from: next.start, by: 60)) { context in
                Text(CalendarRules.countdownText(to: next.start, now: context.date))
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(next.color.color)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
        }
    }
}

/// What the cursor is resting on inside the card.
private enum CalendarFocus: Hashable {
    case rail
    case next
    case join
    case event(String)
}

/// The card: the next event large with its time and a Join button, and a rail of the next few
/// events in their calendars' colours with a marker for now.
struct CalendarExpandedView: View {
    let service: CalendarService

    @State private var focus: CalendarFocus?
    @State private var appeared = false

    var body: some View {
        Group {
            if !service.hasAccess {
                message(symbol: "calendar.badge.exclamationmark",
                        title: L("calendar.noAccess", "Calendar access needed"),
                        detail: L("calendar.noAccess.help", "Grant it in MyNotch Settings → Calendar."))
            } else if service.events.isEmpty {
                message(symbol: "calendar", title: L("calendar.empty", "No meetings left today"), detail: nil)
            } else {
                content
            }
        }
        .foregroundStyle(.white)
        .onAppear { appeared = true }
    }

    private func message(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        let now = Date()
        let events = service.events
        let next = events[0]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(next.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(next.color.color).frame(width: 7, height: 7)
                        Text(CalendarRules.timeRange(next))
                            .monospacedDigit()
                        Text(next.calendarTitle)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .spotlight(CalendarFocus.next, focus: $focus, accent: next.color.color)
                Spacer(minLength: 8)
                countdown(next, now: now)
                if let url = next.joinURL, let provider = next.provider {
                    joinButton(url: url, provider: provider, color: next.color.color)
                }
            }
            .reveal(appeared, index: 0)

            rail(events, now: now)
                .frame(height: 46)
                .spotlight(CalendarFocus.rail, focus: $focus, accent: next.color.color)
                .reveal(appeared, index: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomLeading) {
            if let focus {
                NotchExplanationBubble(text: explanation(for: focus, events: events, now: now), accent: next.color.color)
                    .padding(.bottom, -6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
    }

    private func countdown(_ event: CalendarEvent, now: Date) -> some View {
        TimelineView(.periodic(from: event.start, by: 60)) { context in
            Text(CalendarRules.countdownText(to: event.start, now: context.date))
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(event.color.color)
                .contentTransition(.numericText())
        }
    }

    private func joinButton(url: URL, provider: MeetingProvider, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "video.fill")
            Text(L("calendar.join", "Join"))
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(color, in: Capsule())
        .contentShape(Capsule())
        .notchTap { NSWorkspace.shared.open(url) }
        .spotlight(CalendarFocus.join, focus: $focus, accent: color)
    }

    /// The next hours as a horizontal rail: events as coloured blocks, now as a thin marker.
    private func rail(_ events: [CalendarEvent], now: Date) -> some View {
        let railStart = now.addingTimeInterval(-15 * 60)
        let lastEnd = events.map(\.end).max() ?? now.addingTimeInterval(3 * 3600)
        let span = max(3 * 3600, lastEnd.timeIntervalSince(railStart) + 15 * 60)
        return GeometryReader { proxy in
            let width = proxy.size.width
            let x = Self.position(width: width, start: railStart, span: span)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08))
                ForEach(events) { event in
                    let left = x(event.start)
                    let right = max(x(event.end), left + 6)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(event.color.color.opacity(focus == .event(event.id) ? 1 : 0.8))
                        .overlay(alignment: .leading) {
                            Text(event.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.85))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                        }
                        .frame(width: right - left, height: proxy.size.height - 12)
                        .offset(x: left, y: 6)
                        .spotlight(CalendarFocus.event(event.id), focus: $focus, accent: event.color.color)
                }
                Rectangle()
                    .fill(.white)
                    .frame(width: 1.5, height: proxy.size.height)
                    .offset(x: x(now))
                ForEach(Array(hourMarks(from: railStart, span: span).enumerated()), id: \.offset) { _, mark in
                    Text(mark.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .offset(x: x(mark) + 2, y: proxy.size.height - 10)
                }
            }
        }
    }

    /// Where a date lands on the rail, clamped to its ends.
    private static func position(width: CGFloat, start: Date, span: TimeInterval) -> (Date) -> CGFloat {
        { date in width * CGFloat(min(max(date.timeIntervalSince(start) / span, 0), 1)) }
    }

    private func hourMarks(from start: Date, span: TimeInterval) -> [Date] {
        var marks: [Date] = []
        var cursor = Calendar.current.nextDate(after: start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? start
        let end = start.addingTimeInterval(span)
        while cursor < end, marks.count < 8 {
            marks.append(cursor)
            cursor = cursor.addingTimeInterval(3600)
        }
        return marks
    }

    private func explanation(for focus: CalendarFocus, events: [CalendarEvent], now: Date) -> String {
        switch focus {
        case .rail:
            let hours = Int(max(3 * 3600, (events.map(\.end).max() ?? now).timeIntervalSince(now)) / 3600)
            return CalendarRules.railExplanation(count: events.count, hours: max(3, hours))
        case .next:
            return CalendarRules.nextExplanation(events[0], now: now)
        case .join:
            return events[0].provider.map { CalendarRules.joinExplanation($0) } ?? ""
        case .event(let id):
            guard let event = events.first(where: { $0.id == id }) else { return "" }
            return event.title + " — " + CalendarRules.timeRange(event) + " · " + event.calendarTitle
        }
    }
}
