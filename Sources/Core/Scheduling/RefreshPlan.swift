// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct RefreshToken: Hashable, Sendable {
    let rawValue: Int
}

/// When a registered refresh is allowed to run.
enum RefreshCondition: Hashable, Sendable {
    case always
    case whileIslandVisible
    case whileExpanded
    /// Only while a named piece of UI (e.g. the Permissions pane) is on screen.
    case whileUIVisible(String)
}

/// The power source decides how lazily work runs.
enum PowerState: Sendable {
    case ac
    case battery
    case lowPower

    var intervalMultiplier: Double {
        switch self {
        case .ac: 1
        case .battery: 2
        case .lowPower: 4
        }
    }
}

/// Everything about the system that affects scheduling.
struct RefreshContext: Equatable, Sendable {
    var power: PowerState = .ac
    /// Screens asleep, screen locked, or the user switched away.
    var suspended = false
    var islandVisible = true
    var islandExpanded = false
    var visibleUI: Set<String> = []
}

struct RefreshEntry: Sendable {
    let id: RefreshToken
    /// Seconds between runs on AC power.
    let interval: TimeInterval
    /// Fraction of the interval the system may shift a run by (at least 10%).
    let tolerance: Double
    let condition: RefreshCondition
    let registeredAt: Date
    var lastFired: Date?
}

/// The pure scheduling rules behind `RefreshScheduler` (tested).
enum RefreshPlan {
    static let minimumTolerance = 0.1

    static func isActive(_ entry: RefreshEntry, in context: RefreshContext) -> Bool {
        guard !context.suspended else { return false }
        switch entry.condition {
        case .always: return true
        case .whileIslandVisible: return context.islandVisible
        case .whileExpanded: return context.islandVisible && context.islandExpanded
        case .whileUIVisible(let key): return context.visibleUI.contains(key)
        }
    }

    static func interval(_ entry: RefreshEntry, in context: RefreshContext) -> TimeInterval {
        entry.interval * context.power.intervalMultiplier
    }

    static func leeway(_ entry: RefreshEntry, in context: RefreshContext) -> TimeInterval {
        interval(entry, in: context) * max(entry.tolerance, minimumTolerance)
    }

    static func nextFire(_ entry: RefreshEntry, in context: RefreshContext) -> Date {
        (entry.lastFired ?? entry.registeredAt).addingTimeInterval(interval(entry, in: context))
    }

    /// When to wake next, and how much the system may shift it; nil when idle.
    static func nextDeadline(_ entries: [RefreshEntry], context: RefreshContext) -> (date: Date, leeway: TimeInterval)? {
        let active = entries.filter { isActive($0, in: context) }
        guard let first = active.min(by: { nextFire($0, in: context) < nextFire($1, in: context) }) else { return nil }
        return (nextFire(first, in: context), leeway(first, in: context))
    }

    /// The entries to run at `now`: those due, plus those due within their
    /// tolerance, so nearby work shares one wake-up.
    static func due(_ entries: [RefreshEntry], at now: Date, context: RefreshContext) -> [RefreshToken] {
        entries
            .filter { isActive($0, in: context) && now >= nextFire($0, in: context).addingTimeInterval(-leeway($0, in: context)) }
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
    }
}
