// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// What the installer last did to `~/.claude/settings.json`, so "Remove"
/// can put back exactly what was there.
struct HookInstallRecord: Codable, Equatable, Sendable {
    /// The backup taken before Notched's first write; nil if there was no file.
    var backupPath: String?
    /// SHA-256 (hex) of the file as Notched last wrote it.
    var writtenHash: String
}

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
