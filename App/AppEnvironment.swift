// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns the app's long-lived services. Created once by `AppDelegate`.
@MainActor
final class AppEnvironment {
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

    /// Modules the user has turned on. Settings will own this in task 6.
    var enabledModules: Set<ModuleID> = [] {
        didSet { modules.reconcile(enabled: enabledModules) }
    }

    init() {
        accessibility = AccessibilityOptions()
        let expiryTimer = expiryTimer
        activities = ActivityCoordinator(scheduleWake: { date in expiryTimer.schedule(at: date) })
        modules = ModuleRegistry(moduleTypes: Self.moduleTypes, coordinator: activities)
        fullscreen = FullscreenMonitor()
        islands = IslandManager(accessibility: accessibility, activities: activities, fullscreen: fullscreen)
        expiryTimer.action = { [weak activities] in activities?.expire(at: Date()) }
    }

    func start() {
        modules.reconcile(enabled: enabledModules)
        islands.start()
    }
}
