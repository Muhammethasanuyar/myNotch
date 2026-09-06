import XCTest
@testable import MyNotch

final class CalendarRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, startsIn minutes: Double, length: Double = 30, calendar: String = "work", allDay: Bool = false, declined: Bool = false, url: URL? = nil) -> CalendarEvent {
        CalendarEvent(id: id, title: id.capitalized, start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + length) * 60),
                      isAllDay: allDay, calendarID: calendar, calendarTitle: calendar, color: .fallback, joinURL: url, provider: url.flatMap(CalendarRules.provider(for:)), isDeclined: declined)
    }

    func testMeetingLinksAreRecognisedByHost() {
        XCTAssertEqual(CalendarRules.joinURL(url: URL(string: "https://us02web.zoom.us/j/123"), location: nil, notes: nil)?.host, "us02web.zoom.us")
        XCTAssertEqual(CalendarRules.provider(for: URL(string: "https://meet.google.com/abc-defg")!), .meet)
        XCTAssertEqual(CalendarRules.provider(for: URL(string: "https://teams.microsoft.com/l/meetup-join/x")!), .teams)
        XCTAssertEqual(CalendarRules.provider(for: URL(string: "https://acme.webex.com/meet/me")!), .webex)
        XCTAssertNil(CalendarRules.provider(for: URL(string: "https://example.com/zoom.us")!), "the host, not the path, decides")
        XCTAssertNil(CalendarRules.provider(for: URL(string: "https://notzoom.us/x")!))
    }

    func testLinksAreFoundInLocationAndNotes() {
        let fromNotes = CalendarRules.joinURL(url: URL(string: "https://example.com/agenda"), location: "Room 4", notes: "Dial in: <https://zoom.us/j/999?pwd=1> (or phone)")
        XCTAssertEqual(fromNotes?.absoluteString, "https://zoom.us/j/999?pwd=1", "a non-meeting URL is passed over for the meeting link")
        XCTAssertEqual(CalendarRules.joinURL(url: nil, location: "https://meet.google.com/xyz", notes: nil)?.host, "meet.google.com")
        XCTAssertNil(CalendarRules.joinURL(url: nil, location: "Kitchen", notes: "bring cake"))
    }

    func testVisibleEventsAreFilteredAndOrdered() {
        let events = [
            event("later", startsIn: 120), event("soon", startsIn: 10), event("past", startsIn: -90, length: 30),
            event("allday", startsIn: 5, allDay: true), event("declined", startsIn: 5, declined: true),
            event("other", startsIn: 20, calendar: "home"), event("fourth", startsIn: 300)
        ]
        XCTAssertEqual(CalendarRules.visible(events, selectedCalendarIDs: [], now: now).map(\.id), ["soon", "other", "later"], "three at most, soonest first")
        XCTAssertEqual(CalendarRules.visible(events, selectedCalendarIDs: ["work"], now: now).map(\.id), ["soon", "later", "fourth"])
        XCTAssertEqual(CalendarRules.visible([event("running", startsIn: -10, length: 30)], selectedCalendarIDs: [], now: now).map(\.id), ["running"], "an event under way still counts")
    }

    func testActivityFollowsTheLead() {
        XCTAssertEqual(CalendarRules.activity(next: nil, now: now, leadMinutes: 15), .idle)
        XCTAssertEqual(CalendarRules.activity(next: event("far", startsIn: 40), now: now, leadMinutes: 15), .idle)
        XCTAssertEqual(CalendarRules.activity(next: event("near", startsIn: 15), now: now, leadMinutes: 15), .live)
        XCTAssertEqual(CalendarRules.activity(next: event("running", startsIn: -5), now: now, leadMinutes: 15), .live)
        XCTAssertEqual(CalendarRules.activity(next: event("over", startsIn: -60, length: 30), now: now, leadMinutes: 15), .idle)
    }

    func testNextBoundaryIsTheSoonestFutureMoment() {
        let events = [event("a", startsIn: 40), event("b", startsIn: 100)]
        XCTAssertEqual(CalendarRules.nextBoundary(events: events, now: now, leadMinutes: 15), now.addingTimeInterval(25 * 60), "the lead of the first event")
        let close = [event("c", startsIn: 3)]
        XCTAssertEqual(CalendarRules.nextBoundary(events: close, now: now, leadMinutes: 15), now.addingTimeInterval(3 * 60), "the start, once the warnings have passed")
        XCTAssertNil(CalendarRules.nextBoundary(events: [], now: now, leadMinutes: 15))
    }

    func testAlertsFireOncePerBoundary() {
        let meeting = event("standup", startsIn: 4)
        var result = CalendarRules.alerts(events: [meeting], now: now, announced: [])
        XCTAssertEqual(result.alerts.map(\.1), [.fiveMinutes])
        result = CalendarRules.alerts(events: [meeting], now: now.addingTimeInterval(60), announced: result.announced)
        XCTAssertTrue(result.alerts.isEmpty, "the same warning is not repeated")
        result = CalendarRules.alerts(events: [meeting], now: now.addingTimeInterval(4 * 60 + 5), announced: result.announced)
        XCTAssertEqual(result.alerts.map(\.1), [.starting])
        result = CalendarRules.alerts(events: [meeting], now: now.addingTimeInterval(10 * 60), announced: result.announced)
        XCTAssertTrue(result.alerts.isEmpty)
        let late = CalendarRules.alerts(events: [event("missed", startsIn: -5)], now: now, announced: [])
        XCTAssertTrue(late.alerts.isEmpty, "a start seen five minutes late is not announced")
    }

    func testTextInTheSourceLanguage() {
        let bundle = Bundle(for: CalendarRulesTests.self)
        XCTAssertEqual(CalendarRules.countdownText(to: now.addingTimeInterval(12 * 60 - 1), now: now, bundle: bundle, locale: Locale(identifier: "en_US")), "12m")
        XCTAssertEqual(CalendarRules.countdownText(to: now.addingTimeInterval(-30), now: now, bundle: bundle), "now")
        let meeting = event("standup", startsIn: 5, url: URL(string: "https://zoom.us/j/1"))
        let popup = CalendarRules.popupEvent(for: meeting, kind: .fiveMinutes, moduleID: "calendar", bundle: bundle)
        XCTAssertEqual(popup.title, "Standup in 5 minutes")
        XCTAssertEqual(popup.detail, "work · Zoom")
        XCTAssertEqual(CalendarRules.popupEvent(for: meeting, kind: .starting, moduleID: "calendar", bundle: bundle).title, "Standup is starting")
        XCTAssertEqual(CalendarRules.symbol(for: nil), "calendar.badge.clock")
        XCTAssertEqual(CalendarRules.symbol(for: .meet), "video.fill")
    }
}
