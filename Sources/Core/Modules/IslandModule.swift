// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// What the app shows about a module before it is ever created.
struct ModuleDescriptor: Identifiable, Sendable {
    let id: ModuleID
    let name: String
    /// SF Symbol name.
    let symbol: String
    let summary: String
    /// Requested only when the user turns the module on.
    let permissions: [Permission]
    /// Shown only in DEBUG builds.
    let isDebugOnly: Bool
}

/// A feature of the island (CLAUDE.md "Module contract").
///
/// Modules are off by default. A disabled module is never instantiated, so it
/// costs nothing. `stop()` must release every timer, observer and process.
@MainActor
protocol IslandModule: AnyObject {
    static var descriptor: ModuleDescriptor { get }
    init(context: ModuleContext)
    func start()
    func stop()
    /// An optional settings pane for the Modules section of Settings.
    var settingsPane: AnyView? { get }
}

extension IslandModule {
    var settingsPane: AnyView? { nil }
}

/// What a module may use. Its activity sink is scoped to its own id; any
/// polling goes through the shared scheduler.
@MainActor
struct ModuleContext {
    let activities: ActivitySink
    let scheduler: RefreshScheduler
}

/// Lets one module post and remove its own activities, and only its own.
@MainActor
struct ActivitySink {
    let moduleID: ModuleID
    let coordinator: ActivityCoordinator

    func post(_ activity: Activity) {
        guard activity.moduleID == moduleID else {
            Log.modules.error("Module \(moduleID, privacy: .public) tried to post an activity for \(activity.moduleID, privacy: .public)")
            return
        }
        coordinator.post(activity)
    }

    func remove(_ id: ActivityID) {
        guard coordinator.ranked.contains(where: { $0.id == id && $0.moduleID == moduleID }) else { return }
        coordinator.remove(id)
    }

    func removeAll() {
        coordinator.removeAll(from: moduleID)
    }
}
