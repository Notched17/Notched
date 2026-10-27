// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Decides what the compact island shows when several modules have something
/// live at once (#8). Pure and clock-injected, so its rules are unit-tested
/// (ADR-0004):
///
/// - Activities rank by priority (alert > live session > media > idle), then
///   newest first.
/// - An alert at the top owns both compact slots until it expires.
/// - Otherwise the leading slot comes from the highest-ranked activity with a
///   leading item, and the trailing slot from the highest-ranked one with a
///   trailing item.
/// - When a transient activity expires, the island returns to what it showed before.
@MainActor
@Observable
final class ActivityCoordinator {
    struct Slot {
        let activityID: ActivityID
        let content: ActivityContent
    }

    private(set) var leading: Slot?
    private(set) var trailing: Slot?
    /// Every live activity, best first. The expanded island renders from this.
    private(set) var ranked: [Activity] = []
    /// Increments when a new alert arrives, so the island can bounce.
    private(set) var alertSerial = 0

    private struct Entry {
        var activity: Activity
        var sequence: Int
        var expiresAt: Date?
    }

    @ObservationIgnored private var entries: [ActivityID: Entry] = [:]
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let scheduleWake: @MainActor (Date?) -> Void

    /// - Parameters:
    ///   - now: the clock (injected in tests).
    ///   - scheduleWake: told the next expiry after every change, so the app
    ///     can call `expire(at:)` then. No polling.
    init(now: @escaping () -> Date = Date.init, scheduleWake: @escaping @MainActor (Date?) -> Void = { _ in }) {
        self.now = now
        self.scheduleWake = scheduleWake
    }

    var nextExpiry: Date? {
        entries.values.compactMap(\.expiresAt).min()
    }

    /// Adds an activity, or updates the one with the same id in place.
    func post(_ activity: Activity) {
        let expiresAt: Date? = switch activity.lifetime {
        case .untilRemoved: nil
        case .transient(let duration): now().addingTimeInterval(duration.timeInterval)
        }
        if var existing = entries[activity.id] {
            existing.activity = activity
            existing.expiresAt = expiresAt
            entries[activity.id] = existing
        } else {
            sequence += 1
            entries[activity.id] = Entry(activity: activity, sequence: sequence, expiresAt: expiresAt)
            if activity.priority == .alert { alertSerial += 1 }
        }
        recompute()
    }

    func remove(_ id: ActivityID) {
        guard entries.removeValue(forKey: id) != nil else { return }
        recompute()
    }

    func removeAll(from module: ModuleID) {
        let before = entries.count
        entries = entries.filter { $0.value.activity.moduleID != module }
        if entries.count != before { recompute() }
    }

    /// Drops transient activities whose time has come.
    func expire(at date: Date) {
        let before = entries.count
        entries = entries.filter { entry in entry.value.expiresAt.map { $0 > date } ?? true }
        if entries.count != before {
            recompute()
        } else {
            scheduleWake(nextExpiry)
        }
    }

    private func recompute() {
        let ordered = entries.values.sorted { lhs, rhs in
            if lhs.activity.priority != rhs.activity.priority {
                return lhs.activity.priority > rhs.activity.priority
            }
            return lhs.sequence > rhs.sequence
        }
        ranked = ordered.map(\.activity)

        if let top = ranked.first, top.priority == .alert {
            leading = top.compactLeading.map { Slot(activityID: top.id, content: $0) }
            trailing = top.compactTrailing.map { Slot(activityID: top.id, content: $0) }
        } else {
            leading = ranked.lazy.compactMap { activity in
                activity.compactLeading.map { Slot(activityID: activity.id, content: $0) }
            }.first
            trailing = ranked.lazy.compactMap { activity in
                activity.compactTrailing.map { Slot(activityID: activity.id, content: $0) }
            }.first
        }
        scheduleWake(nextExpiry)
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
