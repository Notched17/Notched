// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation

/// Owns the app's long-lived services and keeps them in step with Settings.
/// Created once by `AppDelegate`.
@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let scheduler: RefreshScheduler
    let permissions: PermissionCenter
    let launchAtLogin: LaunchAtLogin
    let accessibility: AccessibilityOptions
    let activities: ActivityCoordinator
    let modules: ModuleRegistry
    let fullscreen: FullscreenMonitor
    let islands: IslandManager
    #if DEBUG
    /// Demo activities for trying the island (Debug ▸ Scenario Lab).
    private(set) lazy var scenarioLab = ScenarioLab(activities: activities) { [weak modules] seconds in
        (modules?.module(TimersModule.descriptor.id) as? TimersModule)?.startTimer(seconds: seconds, label: "Demo")
    }
    #endif
    private let expiryTimer = OneShotTimer()
    private let power = PowerStateMonitor()
    private let systemActivity = SystemActivityMonitor()

    /// Every module the app knows, in display order.
    static var moduleTypes: [any IslandModule.Type] {
        var types: [any IslandModule.Type] = [
            MediaModule.self, TimersModule.self, KeepAwakeModule.self,
            BatteryModule.self, BluetoothModule.self, NetworkModule.self, CapsLockModule.self,
        ]
        #if DEBUG
        types.append(HelloModule.self)
        #endif
        return types
    }

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        scheduler = RefreshScheduler()
        permissions = PermissionCenter(scheduler: scheduler)
        launchAtLogin = LaunchAtLogin()
        accessibility = AccessibilityOptions()
        let expiryTimer = expiryTimer
        activities = ActivityCoordinator(scheduleWake: { date in expiryTimer.schedule(at: date) })
        modules = ModuleRegistry(moduleTypes: Self.moduleTypes, coordinator: activities, settings: settings, scheduler: scheduler,
                                 services: ModuleServices(audioOutputs: AudioOutputService(), permissions: permissions))
        fullscreen = FullscreenMonitor()
        islands = IslandManager(accessibility: accessibility, activities: activities, fullscreen: fullscreen)
        expiryTimer.action = { [weak activities] in activities?.advance(to: Date()) }
    }

    func start() {
        power.onChange = { [weak self] state in self?.scheduler.context.power = state }
        systemActivity.onChange = { [weak self] suspended in self?.scheduler.context.suspended = suspended }
        power.start()
        systemActivity.start()
        scheduler.context.power = power.state
        applySettings()
        // Modules follow their own setting (ModuleHost), outside the
        // observation below, so what they read while starting isn't tracked.
        modules.start(debuggerAttached: ModuleHost.isDebuggerAttached())
        islands.start()
    }

    /// Pushes every setting to the services, and again whenever one changes.
    private func applySettings() {
        withObservationTracking {
            islands.configuration = settings.islandConfiguration
            islands.behavior = settings.islandBehavior
            islands.appearance = settings.islandAppearance
            activities.configuration = settings.activityConfiguration
            islands.isPaused = settings.isPaused
            scheduler.context.islandVisible = !settings.isPaused
            islands.hideInFullscreen = settings.hideInFullscreen
            islands.keepShowingForMedia = settings.keepShowingForMedia
            islands.hideFromScreenCapture = settings.hideFromScreenCapture
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.applySettings() }
        }
    }
}
