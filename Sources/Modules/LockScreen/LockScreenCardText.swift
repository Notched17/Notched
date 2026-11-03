// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The card's surface. Solid is the default: it stays readable over any wallpaper.
enum LockScreenCardStyle: String, CaseIterable, Sendable {
    case solid, glass
}

/// What the lock-screen card may show, one switch per item (ADR-0031 §4).
/// Anything personal (event titles, lyrics) is off until the user says so.
struct LockScreenCardOptions: Equatable, Sendable {
    /// How the card looks (its surface); the size is part of the placement.
    var style = LockScreenCardStyle.solid
    var showTrack = true
    var showArtwork = true
    var showBattery = true
    var showEvent = true
    /// Off: "Event in 12 min". On: "Standup in 12 min".
    var showEventTitle = false
    var showLyrics = false
}

/// The words on the lock-screen card. Pure, so what the card gives away is
/// tested rather than assumed.
enum LockScreenCardText {
    /// An event that started this recently still counts as "now".
    static let nowGrace: TimeInterval = 300
    /// Events further away than this aren't shown ("next event", not "next week").
    static let horizon: TimeInterval = 12 * 3600

    /// The next event's line, or nil when there is none worth showing.
    /// All-day, cancelled and declined events don't count.
    static func nextEvent(_ events: [CalendarEventSnapshot], now: Date, showTitle: Bool,
                          locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        let candidates = events
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined }
            .filter { $0.end > now && $0.start > now.addingTimeInterval(-nowGrace) && $0.start <= now.addingTimeInterval(horizon) }
            .sorted { $0.start < $1.start }
        guard let event = candidates.first else { return nil }

        let subject: String
        if showTitle, case let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            subject = title
        } else {
            subject = "Event"
        }

        let until = event.start.timeIntervalSince(now)
        if until <= 0 { return "\(subject) now" }
        let minutes = Int((until / 60).rounded(.up))
        if minutes < 60 { return "\(subject) in \(minutes) min" }

        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        style.locale = locale
        return "\(subject) at \(event.start.formatted(style))"
    }

    /// The battery's SF Symbol, in the steps the system's own symbols come in.
    static func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func batteryText(level: Int) -> String { "\(min(max(level, 0), 100))%" }
}
