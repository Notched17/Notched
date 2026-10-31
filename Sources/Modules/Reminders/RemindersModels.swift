// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A reminder, copied out of EventKit so the logic never sees EventKit types.
struct ReminderSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    /// When it's due; nil for a reminder with no date.
    var due: Date?
    /// False for "today" with no time of day.
    var hasTime: Bool
    var listID: String
    var listName: String
    var color: ColorValue
    /// EventKit's scale: 1 high ... 9 low, 0 none.
    var priority: Int
}

/// A list the user can leave out (Settings ▸ Reminders).
struct ReminderListInfo: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var color: ColorValue
}

struct RemindersConfig: Equatable, Sendable {
    /// A banner shortly before a timed reminder is due (off by default).
    var dueSoonBanner = false
    var dueSoonLead: TimeInterval = 15 * 60
    /// How long a ticked box can still be undone before it is saved.
    var undoWindow: TimeInterval = 8
    var excludedLists: Set<String> = []
    var calendar = Calendar.current
}

/// One line of the Today tab's Reminders column.
struct ReminderItem: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var isOverdue: Bool
    var color: ColorValue
    /// Ticked, and can still be undone.
    var isPendingComplete: Bool
}

/// What the optional due-soon banner says.
struct ReminderDueSoon: Equatable, Sendable {
    var id: String
    var title: String
    var due: Date
}
