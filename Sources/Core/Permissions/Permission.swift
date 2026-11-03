// SPDX-License-Identifier: GPL-3.0-or-later

/// A macOS privacy (TCC) permission that a module may need.
enum Permission: String, CaseIterable, Codable, Sendable, Identifiable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case automation
    case calendars
    case reminders
    case bluetooth
    case location
    /// Files & Folders access to ~/Downloads (the Downloads module).
    case downloadsFolder
    /// System audio recording, which per-app volume (process taps) needs. macOS can't
    /// be asked beforehand, so this is only known once a tap has been tried (ADR-0029).
    case audioCapture

    var id: Self { self }
}

extension Permission {
    /// What to ask for when modules are turned on. Automation is left out:
    /// macOS grants it per app, the first time a module actually needs it,
    /// and System Settings lists nothing to allow before then. Audio capture
    /// is left out too: its prompt appears the first time an app's volume is
    /// changed, never when the module is turned on.
    static func requestedUpFront(by modules: [ModuleDescriptor]) -> [Permission] {
        allCases.filter { permission in
            permission != .automation && permission != .audioCapture && modules.contains { $0.permissions.contains(permission) }
        }
    }
}
