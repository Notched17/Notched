// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum CalendarAuthorization: Equatable, Sendable {
    case granted, denied, notDetermined
}

/// A calendar the user can leave out (Settings ▸ Calendar).
struct CalendarInfo: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var color: ColorValue
}

/// An event, copied out of EventKit so the logic never sees EventKit types.
struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
    /// Unique per occurrence (a repeating event shares its identifier).
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var isCancelled: Bool
    /// The user said no to it.
    var isDeclined: Bool
    var calendarID: String
    var calendarName: String
    var color: ColorValue
    var location: String?
    var urlString: String?
    var notes: String?
}

struct CalendarConfig: Equatable, Sendable {
    /// The countdown starts this long before an event.
    var countdownMinutes = 15
    /// Expand the island once, a minute before the start.
    var alertBeforeStart = true
    /// "Now" stays this long after the start.
    var nowGrace: TimeInterval = 300
    var alertLead: TimeInterval = 60
    var excludedCalendars: Set<String> = []
    var calendar = Calendar.current
}

/// What the compact island shows for the next event.
struct CountdownInfo: Equatable, Sendable {
    var eventID: String
    var title: String
    var start: Date
    var end: Date
    var color: ColorValue
    var join: MeetingLink?
    /// Whole minutes to the start, rounded up (so the last minute reads 1m);
    /// 0 once it has started.
    var minutesLeft: Int
    var hasStarted: Bool { minutesLeft == 0 }
}

/// One line of the agenda.
struct AgendaItem: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var isTomorrow: Bool
    var isInProgress: Bool
    var color: ColorValue
    var location: String?
    var join: MeetingLink?
}
