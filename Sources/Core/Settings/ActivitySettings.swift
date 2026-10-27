// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What clicking an activity on the compact island does (ISLAND-BEHAVIOR.md §6).
enum ClickBehavior: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Like a tap on iPhone: open the activity's app (or its default action).
    case open
    /// For people who prefer clicking to hovering: expand the island.
    case expand

    var id: Self { self }

    var title: String {
        switch self {
        case .open: "Opens its app"
        case .expand: "Expands the island"
        }
    }
}

/// How long an ended activity stays in the Recent list.
enum RecentRetention: Int, CaseIterable, Codable, Sendable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case fourHours = 240

    var id: Self { self }

    var duration: Duration { .seconds(rawValue * 60) }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .fourHours: "4 hours"
        }
    }
}

extension CompactLayout.Mode: Identifiable {
    var id: Self { self }

    var title: String {
        switch self {
        case .bubbles: "Bubbles"
        case .sideBySide: "Side by side"
        }
    }
}
