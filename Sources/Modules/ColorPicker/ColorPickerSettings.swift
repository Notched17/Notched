// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// The colour picker's saved recent colours, under `colorpicker.*`.
///
/// Stored as a short list of `#RRGGBB` strings. Anything unreadable is left
/// out, so bad data can't break the picker.
@MainActor
@Observable
final class ColorPickerSettings {
    enum Key {
        static let recents = "colorpicker.recents"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Newest first, at most `ColorPickerReducer.recentLimit`.
    var recents: [ColorValue] {
        didSet { defaults.set(recents.map(\.hex), forKey: Key.recents) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = (defaults.array(forKey: Key.recents) as? [String] ?? []).compactMap(ColorValue.init(hex:))
        recents = Array(saved.prefix(ColorPickerReducer.recentLimit))
    }
}
