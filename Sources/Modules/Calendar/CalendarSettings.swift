// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Calendar's settings (Settings ▸ Modules ▸ Calendar), under `calendar.*`.
@MainActor
@Observable
final class CalendarSettings {
    enum Key {
        static let countdownMinutes = "calendar.countdownMinutes"
        static let alertBeforeStart = "calendar.alertBeforeStart"
        static let excludedCalendars = "calendar.excludedCalendars"
    }

    static let countdownChoices = [5, 10, 15, 30]

    @ObservationIgnored private let defaults: UserDefaults

    /// How long before an event the compact countdown appears.
    var countdownMinutes: Int { didSet { defaults.set(countdownMinutes, forKey: Key.countdownMinutes) } }
    /// Expand the island once, a minute before an event starts.
    var alertBeforeStart: Bool { didSet { defaults.set(alertBeforeStart, forKey: Key.alertBeforeStart) } }
    /// Calendars left out of the agenda and countdown, by EventKit identifier.
    var excludedCalendars: [String] { didSet { defaults.set(excludedCalendars, forKey: Key.excludedCalendars) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Key.countdownMinutes) as? Int ?? 15
        countdownMinutes = Self.countdownChoices.contains(saved) ? saved : 15
        alertBeforeStart = defaults.object(forKey: Key.alertBeforeStart) as? Bool ?? true
        excludedCalendars = defaults.stringArray(forKey: Key.excludedCalendars) ?? []
    }

    var reducerConfig: CalendarConfig {
        CalendarConfig(countdownMinutes: countdownMinutes, alertBeforeStart: alertBeforeStart, excludedCalendars: Set(excludedCalendars))
    }
}
