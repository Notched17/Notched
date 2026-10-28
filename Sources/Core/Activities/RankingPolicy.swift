// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The user's priority for the island (#8). Pure and saved as JSON.
///
/// The order, best first:
/// 1. **System** activities (a call), always. They can't be demoted.
/// 2. Activities from **pinned** modules, in pin order.
/// 3. Everything else, by the user's **class order** (default: Now Playing,
///    then timers/downloads/tools, then status; ADR-0011).
///
/// Within a tier the coordinator still orders by relevance, then start order.
/// The ROADMAP says this "feeds relevance", but a relevance number can't say
/// "this timer beats music" across classes, so the policy changes the
/// comparison itself (ADR-0016). Alerts and the swap rules stay keyed on the
/// activity's kind, not on its rank.
struct RankingPolicy: Equatable, Codable, Sendable {
    /// The classes a user can order; system is fixed on top.
    static let rankable: [ActivityKind] = [.media, .live, .passive]
    static let `default` = RankingPolicy(order: rankable, pinned: [])

    /// Highest first. `normalized()` makes it a permutation of `rankable`.
    var order: [ActivityKind]
    var pinned: [ModuleID]

    /// Where an activity sorts; smaller ranks higher.
    struct Key: Comparable, Hashable, Sendable {
        var group: Int
        var sub: Int

        static func < (lhs: Key, rhs: Key) -> Bool { (lhs.group, lhs.sub) < (rhs.group, rhs.sub) }
    }

    func key(kind: ActivityKind, module: ModuleID) -> Key {
        if kind == .system { return Key(group: 0, sub: 0) }
        if let pin = pinned.firstIndex(of: module) { return Key(group: 1, sub: pin) }
        return Key(group: 2, sub: order.firstIndex(of: kind) ?? Int.max)
    }

    /// Drops system and repeats, and puts any missing class back in its
    /// default slot.
    func normalized() -> RankingPolicy {
        var seen = Set<ActivityKind>()
        var order = self.order.filter { Self.rankable.contains($0) && seen.insert($0).inserted }
        for kind in Self.rankable where !order.contains(kind) {
            order.insert(kind, at: min(Self.rankable.firstIndex(of: kind) ?? order.count, order.count))
        }
        var pins = Set<ModuleID>()
        return RankingPolicy(order: order, pinned: pinned.filter { pins.insert($0).inserted })
    }

    // MARK: Editing (the Priority pane)

    /// Moves a class up (negative) or down (positive) the order, stopping at the ends.
    func moving(_ kind: ActivityKind, by offset: Int) -> RankingPolicy {
        var policy = normalized()
        guard let index = policy.order.firstIndex(of: kind) else { return policy }
        let target = min(max(index + offset, 0), policy.order.count - 1)
        policy.order.insert(policy.order.remove(at: index), at: target)
        return policy
    }

    /// Pins a module below those already pinned.
    func pinning(_ module: ModuleID) -> RankingPolicy {
        guard !pinned.contains(module) else { return self }
        return RankingPolicy(order: order, pinned: pinned + [module])
    }

    func unpinning(_ module: ModuleID) -> RankingPolicy {
        RankingPolicy(order: order, pinned: pinned.filter { $0 != module })
    }

    /// Moves a pinned module up (negative) or down (positive), stopping at the ends.
    func movingPin(_ module: ModuleID, by offset: Int) -> RankingPolicy {
        var pins = normalized().pinned
        guard let index = pins.firstIndex(of: module) else { return self }
        let target = min(max(index + offset, 0), pins.count - 1)
        pins.insert(pins.remove(at: index), at: target)
        return RankingPolicy(order: order, pinned: pins)
    }

    // MARK: Saving

    func encoded() -> Data? { try? JSONEncoder().encode(normalized()) }

    /// What was saved, or the default if there's nothing, or it can't be
    /// read (corrupt, or written by a version that knew more classes).
    static func load(from data: Data?) -> RankingPolicy {
        guard let data, let policy = try? JSONDecoder().decode(RankingPolicy.self, from: data) else { return .default }
        return policy.normalized()
    }
}
