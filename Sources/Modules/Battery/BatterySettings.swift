// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Battery's settings (Settings ▸ Modules ▸ Battery), persisted under `battery.*`.
@MainActor
@Observable
final class BatterySettings {
    enum Key {
        static let firstWarning = "battery.firstWarning"
        static let secondWarning = "battery.secondWarning"
        static let showWhileChargingUntil = "battery.showWhileChargingUntil"
    }

    static let firstWarningChoices = [10, 15, 20, 25, 30]
    static let secondWarningChoices = [5, 10]
    /// 0 is off: banners only.
    static let showWhileChargingChoices = [0, 80, 100]

    @ObservationIgnored private let defaults: UserDefaults

    /// The Low Battery banner's first level; 0 turns it off.
    var firstWarning: Int { didSet { defaults.set(firstWarning, forKey: Key.firstWarning) } }
    /// The second, lower warning; 0 turns it off.
    var secondWarning: Int { didSet { defaults.set(secondWarning, forKey: Key.secondWarning) } }
    /// Show a charging activity until this level; 0 shows banners only.
    var showWhileChargingUntil: Int { didSet { defaults.set(showWhileChargingUntil, forKey: Key.showWhileChargingUntil) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        firstWarning = Self.read(Key.firstWarning, from: defaults, choices: [0] + Self.firstWarningChoices, default: 20)
        secondWarning = Self.read(Key.secondWarning, from: defaults, choices: [0] + Self.secondWarningChoices, default: 10)
        showWhileChargingUntil = Self.read(Key.showWhileChargingUntil, from: defaults, choices: Self.showWhileChargingChoices, default: 0)
    }

    var preferences: BatteryPreferences {
        BatteryPreferences(
            lowThresholds: [firstWarning, secondWarning].filter { $0 > 0 }.sorted(by: >),
            showWhileChargingUntil: showWhileChargingUntil > 0 ? showWhileChargingUntil : nil
        )
    }

    private static func read(_ key: String, from defaults: UserDefaults, choices: [Int], default value: Int) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int, choices.contains(stored) else { return value }
        return stored
    }
}
