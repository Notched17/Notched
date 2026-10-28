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

    var id: Self { self }
}

extension Permission {
    /// What to ask for when modules are turned on. Automation is left out:
    /// macOS grants it per app, the first time a module actually needs it,
    /// and System Settings lists nothing to allow before then.
    static func requestedUpFront(by modules: [ModuleDescriptor]) -> [Permission] {
        allCases.filter { permission in
            permission != .automation && modules.contains { $0.permissions.contains(permission) }
        }
    }
}
