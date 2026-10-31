// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Reminders' settings (Settings ▸ Modules ▸ Reminders), under `reminders.*`.
@MainActor
@Observable
final class RemindersSettings {
    enum Key {
        static let dueSoonBanner = "reminders.dueSoonBanner"
        static let excludedLists = "reminders.excludedLists"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// A short banner 15 minutes before a timed reminder is due.
    var dueSoonBanner: Bool { didSet { defaults.set(dueSoonBanner, forKey: Key.dueSoonBanner) } }
    /// Lists left out, by EventKit identifier.
    var excludedLists: [String] { didSet { defaults.set(excludedLists, forKey: Key.excludedLists) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dueSoonBanner = defaults.object(forKey: Key.dueSoonBanner) as? Bool ?? false
        excludedLists = defaults.stringArray(forKey: Key.excludedLists) ?? []
    }

    var reducerConfig: RemindersConfig {
        RemindersConfig(dueSoonBanner: dueSoonBanner, excludedLists: Set(excludedLists))
    }
}
