// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// Knows every module and runs exactly the enabled ones (#70).
@MainActor
@Observable
final class ModuleRegistry {
    @ObservationIgnored private let moduleTypes: [any IslandModule.Type]
    @ObservationIgnored private let coordinator: ActivityCoordinator
    @ObservationIgnored private let scheduler: RefreshScheduler
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var running: [ModuleID: any IslandModule] = [:]
    /// Which modules run, for Settings to observe. Written by `reconcile`, never read by it.
    private(set) var runningIDs: Set<ModuleID> = []

    init(moduleTypes: [any IslandModule.Type], coordinator: ActivityCoordinator, settings: SettingsStore,
         scheduler: RefreshScheduler = RefreshScheduler()) {
        self.moduleTypes = moduleTypes
        self.coordinator = coordinator
        self.settings = settings
        self.scheduler = scheduler
    }

    var descriptors: [ModuleDescriptor] { moduleTypes.map { $0.descriptor } }

    func isRunning(_ id: ModuleID) -> Bool { running[id] != nil }

    /// The module's settings pane (Settings ▸ Modules), if it has one.
    func settingsPane(for id: ModuleID) -> AnyView? {
        moduleTypes.first { $0.descriptor.id == id }?.settingsPane(ModuleSettingsContext(settings: settings, registry: self))
    }

    func hasSettingsPane(_ id: ModuleID) -> Bool { settingsPane(for: id) != nil }

    /// The running instance of a module, if it is enabled.
    func module(_ id: ModuleID) -> (any IslandModule)? { running[id] }

    /// Starts newly enabled modules and stops (and releases) disabled ones.
    func reconcile(enabled: Set<ModuleID>) {
        for (id, module) in running where !enabled.contains(id) {
            module.stop()
            running[id] = nil
            coordinator.endAll(from: id)
            Log.modules.info("Stopped module \(id, privacy: .public)")
        }
        for type in moduleTypes {
            let id = type.descriptor.id
            guard enabled.contains(id), running[id] == nil else { continue }
            let context = ModuleContext(activities: ActivitySink(moduleID: id, coordinator: coordinator), scheduler: scheduler,
                                        settings: settings)
            let module = type.init(context: context)
            running[id] = module
            module.start()
            Log.modules.info("Started module \(id, privacy: .public)")
        }
        let ids = Set(running.keys)
        if ids != runningIDs { runningIDs = ids }
    }

    func stopAll() {
        reconcile(enabled: [])
    }
}
