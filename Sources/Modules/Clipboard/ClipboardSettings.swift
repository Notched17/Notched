// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Clipboard history's settings (Settings ▸ Modules ▸ Clipboard), under `clipboard.*`.
@MainActor
@Observable
final class ClipboardSettings {
    enum Key {
        static let historyLength = "clipboard.historyLength"
        static let excludedApps = "clipboard.excludedApps"
        static let clearOnQuit = "clipboard.clearOnQuit"
        static let hotkeyEnabled = "clipboard.hotkeyEnabled"
    }

    static let lengthChoices = [50, 100, 200, 500]

    @ObservationIgnored private let defaults: UserDefaults

    /// Unpinned items kept. Pinned items don't count.
    var historyLength: Int {
        didSet { defaults.set(historyLength, forKey: Key.historyLength) }
    }
    /// Bundle identifiers whose copies are never recorded.
    var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Key.excludedApps) }
    }
    /// Empty the history (pinned items stay) when Notched quits.
    var clearOnQuit: Bool { didSet { defaults.set(clearOnQuit, forKey: Key.clearOnQuit) } }
    /// Open the history from the keyboard shortcut. The Clipboard tab and the
    /// menu-bar item work either way.
    var hotkeyEnabled: Bool { didSet { defaults.set(hotkeyEnabled, forKey: Key.hotkeyEnabled) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Key.historyLength) as? Int ?? 200
        historyLength = Self.lengthChoices.contains(saved) ? saved : 200
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? ClipboardPolicy.defaultExcludedApps
        clearOnQuit = defaults.object(forKey: Key.clearOnQuit) as? Bool ?? false
        hotkeyEnabled = defaults.object(forKey: Key.hotkeyEnabled) as? Bool ?? true
    }

    var reducerConfig: ClipboardReducer.Config {
        ClipboardReducer.Config(limit: historyLength, excludedApps: Set(excludedApps), clearOnQuit: clearOnQuit)
    }
}
