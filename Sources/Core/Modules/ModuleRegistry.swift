// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// The catalogue of every module the app knows (#70): descriptors and
/// settings panes. Running them is `ModuleHost`'s job; the registry forwards
/// to its host so Settings has one place to ask.
@MainActor
@Observable
final class ModuleRegistry {
    @ObservationIgnored let host: ModuleHost
    @ObservationIgnored private let moduleTypes: [any IslandModule.Type]
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let permissions: PermissionCenter?

    init(moduleTypes: [any IslandModule.Type], coordinator: ActivityCoordinator, settings: SettingsStore,
         scheduler: RefreshScheduler = RefreshScheduler(), services: ModuleServices = ModuleServices()) {
        self.moduleTypes = moduleTypes
        self.settings = settings
        permissions = services.permissions
        host = ModuleHost(moduleTypes: moduleTypes, coordinator: coordinator, settings: settings,
                          scheduler: scheduler, services: services)
    }

    /// Every module this Mac can use, in display order.
    var descriptors: [ModuleDescriptor] { host.descriptors }

    /// Which modules run, for Settings to observe.
    var runningIDs: Set<ModuleID> { host.runningIDs }
    var suspendedIDs: Set<ModuleID> { host.suspendedIDs }
    var isSafeMode: Bool { host.isSafeMode }

    func isRunning(_ id: ModuleID) -> Bool { host.module(id) != nil }

    /// The module's settings pane (Settings ▸ Modules), if it has one.
    func settingsPane(for id: ModuleID) -> AnyView? {
        moduleTypes.first { $0.descriptor.id == id }?.settingsPane(ModuleSettingsContext(settings: settings, registry: self, permissions: permissions))
    }

    func hasSettingsPane(_ id: ModuleID) -> Bool { settingsPane(for: id) != nil }

    /// The running instance of a module, if it is enabled.
    func module(_ id: ModuleID) -> (any IslandModule)? { host.module(id) }

    /// Runs the enabled modules and follows the setting (at launch).
    func start(debuggerAttached: Bool) { host.start(debuggerAttached: debuggerAttached) }

    /// Starts newly enabled modules and stops (and releases) disabled ones.
    func reconcile(enabled: Set<ModuleID>) { host.reconcile(enabled: enabled) }

    func stopAll() { host.stopAll() }

    /// Stops every module and records a clean quit (at termination).
    func shutDown() { host.shutDown() }

    func resume(_ id: ModuleID) { host.resume(id) }

    /// Starts the enabled modules after safe mode.
    func leaveSafeMode() { host.leaveSafeMode() }
}
