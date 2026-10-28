// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How much a banner matters when several wait for the island.
enum BannerPriority: Int, Comparable, Sendable {
    /// A device disconnecting.
    case low
    case normal
    /// Low battery: waits longer and goes first.
    case high

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Banners waiting for the island while an alert shows, the user is on the
/// island, or another banner is up (ADR-0012). Pure.
///
/// - The same id replaces its queued copy: ids are categories ("network",
///   "capslock"), so only the latest state of each waits.
/// - The next banner is the most important, then the one that came first.
/// - A banner that waited too long is old news and is dropped (5 s; 30 s
///   for `.high`).
/// - At most `capacity` wait; over that, the oldest of the least important goes.
struct BannerQueue<Payload> {
    struct Entry {
        let id: String
        let priority: BannerPriority
        let postedAt: Date
        let payload: Payload
    }

    static var capacity: Int { 3 }

    static func maxWait(_ priority: BannerPriority) -> TimeInterval {
        priority == .high ? 30 : 5
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    mutating func enqueue(id: String, priority: BannerPriority, payload: Payload, at date: Date) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, priority: priority, postedAt: date, payload: payload))
        guard entries.count > Self.capacity else { return }
        let lowest = entries.map(\.priority).min() ?? .low
        if let index = entries.indices.filter({ entries[$0].priority == lowest }).min(by: { entries[$0].postedAt < entries[$1].postedAt }) {
            entries.remove(at: index)
        }
    }

    mutating func removeAll(where shouldRemove: (_ id: String, _ payload: Payload) -> Bool) {
        entries.removeAll { shouldRemove($0.id, $0.payload) }
    }

    /// Takes the next banner to show, dropping any that waited too long.
    mutating func next(at date: Date) -> (id: String, payload: Payload)? {
        entries.removeAll { date.timeIntervalSince($0.postedAt) > Self.maxWait($0.priority) }
        guard let index = entries.indices.min(by: { lhs, rhs in
            let a = entries[lhs], b = entries[rhs]
            return a.priority != b.priority ? a.priority > b.priority : a.postedAt < b.postedAt
        }) else { return nil }
        let entry = entries.remove(at: index)
        return (entry.id, entry.payload)
    }
}
