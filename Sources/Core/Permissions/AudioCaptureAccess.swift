// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The system-audio-recording permission, as far as Notched can know it.
/// Core Audio has no call that reports it (`TCCAccessPreflight` answers
/// "unknown" both before and after the user allows it), so the status is
/// what the mixer last learned from a real tap: sound arrived (granted), or
/// only silence did while the app was playing (probably refused). ADR-0029.
enum AudioCaptureAccess {
    static let defaultsKey = "permissions.audioCapture"

    enum Result: String, Sendable {
        case granted
        case denied
    }

    static func status(defaults: UserDefaults = .standard) -> PermissionStatus {
        switch defaults.string(forKey: defaultsKey).flatMap(Result.init(rawValue:)) {
        case .granted: .granted
        case .denied: .denied
        case nil: .notDetermined
        }
    }

    static func record(_ result: Result, defaults: UserDefaults = .standard) {
        defaults.set(result.rawValue, forKey: defaultsKey)
    }
}
