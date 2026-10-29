// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Camera & Microphone's settings (Settings ▸ Modules ▸ Camera & Microphone),
/// persisted under `sensors.*`.
@MainActor
@Observable
final class SensorsSettings {
    enum Key {
        static let showMicrophone = "sensors.showMicrophone"
        static let showCamera = "sensors.showCamera"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showMicrophone: Bool { didSet { defaults.set(showMicrophone, forKey: Key.showMicrophone) } }
    var showCamera: Bool { didSet { defaults.set(showCamera, forKey: Key.showCamera) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showMicrophone = defaults.object(forKey: Key.showMicrophone) as? Bool ?? true
        showCamera = defaults.object(forKey: Key.showCamera) as? Bool ?? true
    }

    var preferences: SensorIndicatorReducer.Preferences {
        .init(showMicrophone: showMicrophone, showCamera: showCamera)
    }
}
