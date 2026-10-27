// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns the app's long-lived services. Created once by `AppDelegate`.
@MainActor
final class AppEnvironment {
    let accessibility: AccessibilityOptions
    let fullscreen: FullscreenMonitor
    let islands: IslandManager

    init() {
        accessibility = AccessibilityOptions()
        fullscreen = FullscreenMonitor()
        islands = IslandManager(accessibility: accessibility, fullscreen: fullscreen)
    }

    func start() {
        islands.start()
    }
}
