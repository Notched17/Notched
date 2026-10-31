// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Reminders' rules (#50): today's and overdue reminders, a tick that can be
/// undone for a few seconds before it is saved, and an optional due-soon
/// banner. Pure; the shell fetches from EventKit and carries out the effects.
///
/// - **Undo window.** Ticking a box shows it done at once but writes nothing
///   to EventKit until the window (8 s) runs out, so an undo never has to
///   reverse something that already synced to iCloud. Quitting saves what is
///   still pending. A reminder that disappears meanwhile (done elsewhere,
///   deleted) is dropped without a save.
/// - **Order.** Overdue first, then today; each by due time, timed before date-only.
/// - **Banner.** Once per reminder, `dueSoonLead` before a timed one is due;
///   at most three at a time, never for one that is ticked or already overdue.
/// - Without access, nothing is listed.
struct RemindersReducer: Sendable {
    static let maxBannersAtOnce = 3

    struct State: Equatable, Sendable {
        var config = RemindersConfig()
        var hasAccess = false
        var reminders: [ReminderSnapshot] = []
        /// Ticked, waiting out the undo window: id → when it is saved.
        var pending: [String: Date] = [:]
        /// Saved a moment ago; hidden until the store reports back.
        var committing: Set<String> = []
        var announced: Set<String> = []
        var items: [ReminderItem] = []
        var scheduledWake: Date?
    }

    enum Event: Equatable, Sendable {
        case configure(RemindersConfig)
        case access(Bool)
        /// Incomplete reminders due by the end of today (or overdue).
        case reminders([ReminderSnapshot])
        case complete(String)
        case undo(String)
        case tick
        /// The save for this reminder failed: show it again.
        case commitFailed(String)
        /// Notched is quitting: save what is pending now.
        case quit
    }

    enum Effect: Equatable, Sendable {
        case itemsChanged([ReminderItem])
        /// Mark this reminder complete in EventKit.
        case commit(String)
        case dueSoon(ReminderDueSoon)
        case wake(Date?)
    }

    private(set) var state = State()

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .configure(let config): state.config = config
        case .access(let granted):
            state.hasAccess = granted
            if !granted { state.pending = [:] }
        case .reminders(let list):
            state.reminders = list
            // The store has spoken: anything saved a moment ago is either gone or genuinely still open.
            state.committing = []
            // Done elsewhere or deleted while waiting: nothing left to save.
            let present = Set(list.map(\.id))
            state.pending = state.pending.filter { present.contains($0.key) }
        case .complete(let id):
            guard state.reminders.contains(where: { $0.id == id }), state.pending[id] == nil,
                  !state.committing.contains(id), state.hasAccess else { break }
            state.pending[id] = now.addingTimeInterval(state.config.undoWindow)
        case .undo(let id):
            state.pending[id] = nil
        case .tick:
            break
        case .commitFailed(let id):
            state.committing.remove(id)
        case .quit:
            for id in state.pending.keys.sorted() { effects.append(.commit(id)) }
            state.pending = [:]
            return effects + evaluate(now: now)
        }
        effects += commitDue(now: now)
        return effects + evaluate(now: now)
    }

    // MARK: Evaluation

    /// Saves every ticked reminder whose window has run out.
    private mutating func commitDue(now: Date) -> [Effect] {
        let due = state.pending.filter { $0.value <= now }.map(\.key).sorted()
        for id in due {
            state.pending[id] = nil
            state.committing.insert(id)
        }
        return due.map { .commit($0) }
    }

    private mutating func evaluate(now: Date) -> [Effect] {
        var effects: [Effect] = []
        let items = state.hasAccess ? makeItems(now: now) : []
        if items != state.items {
            state.items = items
            effects.append(.itemsChanged(items))
        }
        if state.hasAccess, state.config.dueSoonBanner {
            effects += dueSoon(now: now)
        }
        let wake = nextWake(now: now)
        if wake != state.scheduledWake {
            state.scheduledWake = wake
            effects.append(.wake(wake))
        }
        return effects
    }

    private func isListed(_ reminder: ReminderSnapshot) -> Bool {
        !state.config.excludedLists.contains(reminder.listID) && !state.committing.contains(reminder.id)
    }

    private func isOverdue(_ reminder: ReminderSnapshot, now: Date) -> Bool {
        guard let due = reminder.due else { return false }
        if reminder.hasTime { return due < now }
        return due < state.config.calendar.startOfDay(for: now)
    }

    private func makeItems(now: Date) -> [ReminderItem] {
        let calendar = state.config.calendar
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let visible = state.reminders.filter { reminder in
            guard isListed(reminder) else { return false }
            guard let due = reminder.due, let endOfToday else { return false }
            return due < endOfToday
        }
        let sorted = visible.sorted { lhs, rhs in
            let l = (isOverdue(lhs, now: now) ? 0 : 1, lhs.hasTime ? 0 : 1, lhs.due ?? .distantFuture, lhs.priority == 0 ? 10 : lhs.priority, lhs.title, lhs.id)
            let r = (isOverdue(rhs, now: now) ? 0 : 1, rhs.hasTime ? 0 : 1, rhs.due ?? .distantFuture, rhs.priority == 0 ? 10 : rhs.priority, rhs.title, rhs.id)
            return l < r
        }
        return sorted.map { reminder in
            ReminderItem(id: reminder.id, title: reminder.title, due: reminder.due, hasTime: reminder.hasTime,
                         isOverdue: isOverdue(reminder, now: now), color: reminder.color, isPendingComplete: state.pending[reminder.id] != nil)
        }
    }

    private mutating func dueSoon(now: Date) -> [Effect] {
        let lead = state.config.dueSoonLead
        let candidates = state.reminders
            .filter { reminder in
                guard isListed(reminder), reminder.hasTime, let due = reminder.due, state.pending[reminder.id] == nil,
                      !state.announced.contains(reminder.id) else { return false }
                return due > now && due.timeIntervalSince(now) <= lead
            }
            .sorted { ($0.due ?? .distantFuture, $0.id) < ($1.due ?? .distantFuture, $1.id) }
        var effects: [Effect] = []
        for reminder in candidates {
            state.announced.insert(reminder.id)
            if effects.count < Self.maxBannersAtOnce, let due = reminder.due {
                effects.append(.dueSoon(ReminderDueSoon(id: reminder.id, title: reminder.title, due: due)))
            }
        }
        return effects
    }

    /// The soonest moment anything above could change.
    private func nextWake(now: Date) -> Date? {
        guard state.hasAccess else { return nil }
        let calendar = state.config.calendar
        var candidates: [Date] = Array(state.pending.values)
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) { candidates.append(midnight) }
        for reminder in state.reminders where isListed(reminder) {
            guard reminder.hasTime, let due = reminder.due else { continue }
            candidates.append(due)      // becomes overdue
            if state.config.dueSoonBanner, !state.announced.contains(reminder.id) { candidates.append(due - state.config.dueSoonLead) }
        }
        return candidates.filter { $0 > now }.min()
    }
}
