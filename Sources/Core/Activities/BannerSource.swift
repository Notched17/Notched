// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How eagerly a stream of states is announced as banners (ADR-0012).
struct BannerPolicy: Equatable, Sendable {
    /// A change must last this long before it's announced, so a brief flap
    /// (Wi-Fi dropping for a second) says nothing.
    var settle: TimeInterval = 0
    /// The same value isn't announced again within this time (a loose
    /// charger connector).
    var cooldown: TimeInterval = 0
    /// At most this many announcements per `window`; nil for no limit.
    var maxPerWindow: Int?
    var window: TimeInterval = 60
}

/// Turns a stream of states from a module into the banners worth showing.
/// Pure: the module feeds it values and the time, and schedules a wake when
/// asked.
///
/// - The first value (or `seed`) is the starting state and is never announced.
/// - A change is announced once it has lasted `settle`. A change that
///   reverts in the meantime says nothing.
/// - While the rate limit holds a change back, later changes replace it:
///   only the latest state is announced, never the steps in between.
struct BannerSource<Value: Equatable & Sendable>: Sendable {
    enum Output: Equatable, Sendable {
        case none
        /// Show a banner for this value.
        case emit(Value)
        /// Call `advance(to:)` at this date.
        case wake(Date)
    }

    private struct Emission: Sendable {
        let value: Value
        let date: Date
    }

    let policy: BannerPolicy
    /// The state the user last saw announced (or the starting state).
    private(set) var shown: Value?
    private var pending: Value?
    private var pendingSince: Date?
    private var history: [Emission] = []

    init(policy: BannerPolicy) {
        self.policy = policy
    }

    /// Sets the current state without announcing it.
    mutating func seed(_ value: Value) {
        shown = value
        pending = nil
        pendingSince = nil
    }

    mutating func receive(_ value: Value, at date: Date) -> Output {
        guard shown != nil else {
            seed(value)
            return .none
        }
        if value == shown {
            pending = nil
            pendingSince = nil
            return .none
        }
        if value != pending {
            pending = value
            pendingSince = date
        }
        return advance(to: date)
    }

    mutating func advance(to date: Date) -> Output {
        guard let pending, let since = pendingSince else { return .none }
        let due = since.addingTimeInterval(policy.settle)
        if date < due { return .wake(due) }
        let memory = max(policy.cooldown, policy.window)
        history.removeAll { date.timeIntervalSince($0.date) >= memory }
        if history.contains(where: { $0.value == pending && date.timeIntervalSince($0.date) < policy.cooldown }) {
            // Announced a moment ago: take it as the state, quietly.
            seed(pending)
            return .none
        }
        if let limit = policy.maxPerWindow {
            let recent = history.filter { date.timeIntervalSince($0.date) < policy.window }
            if recent.count >= limit, let oldest = recent.map(\.date).min() {
                return .wake(oldest.addingTimeInterval(policy.window))
            }
        }
        history.append(Emission(value: pending, date: date))
        seed(pending)
        return .emit(pending)
    }
}
