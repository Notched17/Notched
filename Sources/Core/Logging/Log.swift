// SPDX-License-Identifier: GPL-3.0-or-later

import os

/// One `os.Logger` subsystem per area or module, as CLAUDE.md asks.
/// Filter everything with: `log stream --predicate 'subsystem BEGINSWITH "me.rkck.Notched"'`.
enum Log {
    static let root = "me.rkck.Notched"

    static let app = Logger(subsystem: "\(root).app", category: "lifecycle")
    static let island = Logger(subsystem: "\(root).island", category: "island")
    static let geometry = Logger(subsystem: "\(root).island", category: "geometry")
    static let displays = Logger(subsystem: "\(root).displays", category: "displays")
    static let activities = Logger(subsystem: "\(root).activities", category: "coordinator")
    static let modules = Logger(subsystem: "\(root).modules", category: "registry")
    static let scheduler = Logger(subsystem: "\(root).scheduling", category: "scheduler")
    static let permissions = Logger(subsystem: "\(root).permissions", category: "permissions")
    static let settings = Logger(subsystem: "\(root).settings", category: "settings")
    static let privateAPI = Logger(subsystem: "\(root).private", category: "private-api")

    /// A logger for a feature module, e.g. `Log.module("hello")`.
    static func module(_ id: String) -> Logger {
        Logger(subsystem: "\(root).modules.\(id)", category: id)
    }
}
