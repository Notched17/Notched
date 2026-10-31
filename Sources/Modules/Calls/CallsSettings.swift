// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Calls' settings (Settings ▸ Modules ▸ Calls), persisted under `calls.*`.
@MainActor
@Observable
final class CallsSettings {
    enum Key {
        static let browsers = "calls.browsers"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Browsers (bundle IDs) whose microphone use counts as a call, e.g. for
    /// Google Meet. None by default: a browser also uses the microphone for
    /// dictation and sound tests.
    var browsers: Set<String> { didSet { defaults.set(browsers.sorted(), forKey: Key.browsers) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        browsers = Set(defaults.array(forKey: Key.browsers) as? [String] ?? [])
    }

    func binding(for browser: String) -> Bool {
        browsers.contains(browser)
    }

    func set(_ browser: String, enabled: Bool) {
        if enabled { browsers.insert(browser) } else { browsers.remove(browser) }
    }
}
