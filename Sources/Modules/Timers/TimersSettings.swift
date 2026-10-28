// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Timers' settings (Settings ▸ Modules ▸ Timers) and its saved timers,
/// persisted under `timers.*`.
@MainActor
@Observable
final class TimersSettings {
    enum Key {
        static let sound = "timers.sound"
        static let state = "timers.state"
    }

    static let defaultSound = "Glass"
    static let soundsFolder = URL(fileURLWithPath: "/System/Library/Sounds")

    @ObservationIgnored private let defaults: UserDefaults

    /// A system sound's name, played when a timer ends; empty for none.
    var sound: String { didSet { defaults.set(sound, forKey: Key.sound) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sound = defaults.string(forKey: Key.sound) ?? Self.defaultSound
    }

    /// Running, paused and just-finished timers, so they survive a relaunch.
    /// Not observed: it changes with every timer action.
    var savedState: TimersState? {
        defaults.data(forKey: Key.state).flatMap { try? JSONDecoder().decode(TimersState.self, from: $0) }
    }

    func save(_ state: TimersState) {
        if state.timers.isEmpty && state.stopwatch == nil {
            defaults.removeObject(forKey: Key.state)
        } else if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Key.state)
        }
    }

    /// The system's alert sounds (Basso, Glass, Ping…), by name.
    static var availableSounds: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: soundsFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["aiff", "aif", "caf", "wav"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}
