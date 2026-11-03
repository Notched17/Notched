// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Bluetooth's settings (Settings ▸ Modules ▸ Bluetooth), persisted under `bluetooth.*`.
@MainActor
@Observable
final class BluetoothSettings {
    enum Key {
        static let includeAccessories = "bluetooth.includeAccessories"
        static let announceDisconnects = "bluetooth.announceDisconnects"
        static let showBattery = "bluetooth.showBattery"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Keyboards, mice, trackpads and game controllers, as well as audio devices.
    var includeAccessories: Bool { didSet { defaults.set(includeAccessories, forKey: Key.includeAccessories) } }
    var announceDisconnects: Bool { didSet { defaults.set(announceDisconnects, forKey: Key.announceDisconnects) } }
    /// The battery level in the connect banner (#28, ADR-0030).
    var showBattery: Bool { didSet { defaults.set(showBattery, forKey: Key.showBattery) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        includeAccessories = defaults.object(forKey: Key.includeAccessories) as? Bool ?? true
        announceDisconnects = defaults.object(forKey: Key.announceDisconnects) as? Bool ?? true
        showBattery = defaults.object(forKey: Key.showBattery) as? Bool ?? true
    }
}
