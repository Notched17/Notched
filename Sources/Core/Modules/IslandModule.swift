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

/// Lets one module post, end and announce its own activities, and only its own.
@MainActor
struct ActivitySink {
    let moduleID: ModuleID
    let coordinator: ActivityCoordinator

    /// Adds an activity, or updates the one with the same id in place. An
    /// alert expands the island for it briefly (ISLAND-BEHAVIOR.md §1).
    func post(_ activity: LiveActivity, alert: AlertRequest? = nil) {
        guard activity.moduleID == moduleID else {
            Log.modules.error("Module \(moduleID, privacy: .public) tried to post an activity for \(activity.moduleID, privacy: .public)")
            return
        }
        coordinator.post(activity, alert: alert)
    }

    /// Takes an activity off the island at once; it stays under Recent per `dismissal`.
    func end(_ id: ActivityID, dismissal: DismissalPolicy = .default) {
        guard coordinator.live.contains(where: { $0.id == id && $0.activity.moduleID == moduleID }) else { return }
        coordinator.end(id, dismissal: dismissal)
    }

    /// Shows a short wide banner for a system event.
    func show(_ banner: TransientBanner) {
        guard banner.moduleID == moduleID else {
            Log.modules.error("Module \(moduleID, privacy: .public) tried to show a banner for \(banner.moduleID, privacy: .public)")
            return
        }
        coordinator.show(banner)
    }

    /// Removes everything this module shows, without Recent entries.
    func endAll() {
        coordinator.endAll(from: moduleID)
    }
}
