// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Why the HUD turned itself off, and when. Kept until the user turns it back on.
struct HUDLatch: Codable, Equatable, Sendable {
    let reason: HUDStopReason
    let date: Date
}

/// What the HUD module's pane shows.
enum HUDStatus: Equatable, Sendable {
    case running
    /// Pause HUD Replacement is on.
    case paused
    case latched(HUDLatch)
    /// No tap: Accessibility isn't allowed, or the system refused the tap.
    case notAllowed
}

/// The HUD's settings (Settings ▸ Modules ▸ Volume & Brightness), persisted
/// under `hud.*`. Writes reach UserDefaults at once, so the crash bookkeeping
/// survives the app crashing.
@MainActor
@Observable
final class HUDSettings {
    enum Key {
        static let isPaused = "hud.isPaused"
        static let armedSession = "hud.armedSession"
        static let uncleanStreak = "hud.uncleanStreak"
        static let latch = "hud.latch"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Pause HUD Replacement: the keys are left to macOS until it's turned off.
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.isPaused) } }
    /// Set while the tap is installed, cleared when it's removed and on a clean
    /// quit. Still set at the next launch means the app ended while armed.
    var armedSession: Bool { didSet { defaults.set(armedSession, forKey: Key.armedSession) } }
    /// Sessions in a row that ended while armed (`HUDLatchRule`).
    var uncleanStreak: Int { didSet { defaults.set(uncleanStreak, forKey: Key.uncleanStreak) } }
    /// Set when the HUD turned itself off; no tap is installed while it is.
    var latch: HUDLatch? {
        didSet {
            if let latch, let data = try? JSONEncoder().encode(latch) {
                defaults.set(data, forKey: Key.latch)
            } else {
                defaults.removeObject(forKey: Key.latch)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPaused = defaults.bool(forKey: Key.isPaused)
        armedSession = defaults.bool(forKey: Key.armedSession)
        uncleanStreak = defaults.integer(forKey: Key.uncleanStreak)
        latch = defaults.data(forKey: Key.latch).flatMap { try? JSONDecoder().decode(HUDLatch.self, from: $0) }
    }
}
