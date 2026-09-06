import EventKit
import Foundation

/// What the module may read from the calendar database.
nonisolated enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess: self = .authorized
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied, .writeOnly: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// Where a meeting link points, for the glyph beside the housing.
nonisolated enum MeetingProvider: String, Equatable, Sendable {
    case zoom
    case meet
    case teams
    case webex
    case other
}

/// A calendar's colour, kept as plain numbers so events stay `Sendable`.
nonisolated struct CalendarColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let fallback = CalendarColor(red: 0.45, green: 0.6, blue: 1.0)
}

/// One upcoming event, reduced to what the notch shows.
nonisolated struct CalendarEvent: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let color: CalendarColor
    let joinURL: URL?
    let provider: MeetingProvider?
    /// The current user declined; such events never come up.
    let isDeclined: Bool
}

/// Where a boundary popup sits relative to the start.
nonisolated enum CalendarAlertKind: Equatable, Sendable {
    case fiveMinutes
    case starting
}
