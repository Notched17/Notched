// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns the app's long-lived services. Created once by `AppDelegate`.
@MainActor
final class AppEnvironment {
    let islands: IslandManager

    init() {
        islands = IslandManager()
    }

    func start() {
        islands.start()
    }
}
