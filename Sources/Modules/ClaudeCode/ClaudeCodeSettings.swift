// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Claude Code's settings (Settings ▸ Modules ▸ Claude Code), persisted under `claudecode.*`.
@MainActor
@Observable
final class ClaudeCodeSettings {
    enum Key {
        static let status = "claudecode.status"
        static let usage = "claudecode.usage"
        static let installRecord = "claudecode.hooks.record"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Show Claude Code's work on the island and answer its permission requests.
    var statusEnabled: Bool { didSet { defaults.set(statusEnabled, forKey: Key.status) } }
    /// Show the AI tab with token usage.
    var usageEnabled: Bool { didSet { defaults.set(usageEnabled, forKey: Key.usage) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        statusEnabled = defaults.object(forKey: Key.status) as? Bool ?? true
        usageEnabled = defaults.object(forKey: Key.usage) as? Bool ?? true
    }

    var installRecord: HookInstallRecord? {
        get { defaults.data(forKey: Key.installRecord).flatMap { try? JSONDecoder().decode(HookInstallRecord.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.installRecord)
            } else {
                defaults.removeObject(forKey: Key.installRecord)
            }
        }
    }
}
