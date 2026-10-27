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
