// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import ServiceManagement

/// Opens Notched at login through `SMAppService.mainApp` (#77). The state
/// lives in macOS (System Settings > General > Login Items), so it's read back
/// rather than stored.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    @ObservationIgnored private let observers = NotificationTokens()

    init() {
        refresh()
        observers.observe(NSApplication.didBecomeActiveNotification) { [weak self] in self?.refresh() }
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    /// The user turned it off in System Settings, so macOS needs their approval.
    var requiresApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Launch at login: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refresh() {
        let current = SMAppService.mainApp.status
        if current != status { status = current }
    }
}
