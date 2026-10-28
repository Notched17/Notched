// SPDX-License-Identifier: GPL-3.0-or-later

extension Permission {
    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen Recording"
        case .automation: "Automation"
        case .calendars: "Calendars"
        case .reminders: "Reminders"
        case .bluetooth: "Bluetooth"
        case .location: "Location"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .automation: "gearshape.2"
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .location: "location"
        }
    }

    /// Why Notched might ask, in one sentence.
    var purpose: String {
        switch self {
        case .accessibility: "Replace the volume and brightness HUDs."
        case .inputMonitoring: "Notice media keys. (Caps Lock doesn't need it.)"
        case .screenRecording: "Not used by any current module."
        case .automation: "Control Music and Spotify."
        case .calendars: "Show your upcoming events."
        case .reminders: "Show and complete today's reminders."
        case .bluetooth: "Show when headphones connect."
        case .location: "Show local weather."
        }
    }
}
