// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns the app's long-lived services. Created once by `AppDelegate`.
@MainActor
final class AppEnvironment {
    let accessibility: AccessibilityOptions
    let islands: IslandManager

    init() {
        accessibility = AccessibilityOptions()
        islands = IslandManager(accessibility: accessibility)
    }

    func start() {
        islands.start()
    }
}
