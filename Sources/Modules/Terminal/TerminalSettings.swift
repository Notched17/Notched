// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// The terminal's settings (Settings ▸ Modules ▸ Terminal), under `terminal.*`.
@MainActor
@Observable
final class TerminalSettings {
    enum Key {
        static let fontSize = "terminal.fontSize"
    }

    static let fontSizes = [10, 11, 12, 13, 14, 16]
    static let defaultFontSize = 11

    @ObservationIgnored private let defaults: UserDefaults

    var fontSize: Int { didSet { defaults.set(fontSize, forKey: Key.fontSize) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Key.fontSize) as? Int ?? Self.defaultFontSize
        fontSize = Self.fontSizes.contains(saved) ? saved : Self.defaultFontSize
    }
}
