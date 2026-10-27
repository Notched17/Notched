// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation

/// Owns the app's long-lived services and keeps them in step with Settings.
/// Created once by `AppDelegate`.
@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let accessibility: AccessibilityOptions
    let activities: ActivityCoordinator
    let modules: ModuleRegistry
    let fullscreen: FullscreenMonitor
    let islands: IslandManager
    private let expiryTimer = OneShotTimer()

    /// Every module the app knows, in display order.
    static var moduleTypes: [any IslandModule.Type] {
        var types: [any IslandModule.Type] = []
        #if DEBUG
        types.append(HelloModule.self)
        #endif
        return types
    }

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        accessibility = AccessibilityOptions()
        let expiryTimer = expiryTimer
        activities = ActivityCoordinator(scheduleWake: { date in expiryTimer.schedule(at: date) })
        modules = ModuleRegistry(moduleTypes: Self.moduleTypes, coordinator: activities)
        fullscreen = FullscreenMonitor()
        islands = IslandManager(accessibility: accessibility, activities: activities, fullscreen: fullscreen)
        expiryTimer.action = { [weak activities] in activities?.expire(at: Date()) }
    }

    func start() {
        applySettings()
        islands.start()
    }

    /// Pushes every setting to the services, and again whenever one changes.
    private func applySettings() {
        withObservationTracking {
            islands.configuration = settings.islandConfiguration
            islands.behavior = settings.islandBehavior
            islands.appearance = IslandAppearance(
                notchTheme: settings.notchTheme,
                pillTheme: settings.pillTheme,
                expandedScale: settings.expandedScale
            )
            islands.isPaused = settings.isPaused
            islands.hideInFullscreen = settings.hideInFullscreen
            islands.hideFromScreenCapture = settings.hideFromScreenCapture
            modules.reconcile(enabled: settings.enabledModules)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.applySettings() }
        }
    }
}
