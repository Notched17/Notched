// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What one look at the Downloads folder found. Built by the watcher; the
/// reducer never touches the file system.
struct DownloadsScan: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        /// The finished file's name, or the partial name for an unconfirmed Chrome download.
        var key: String
        var name: String
        var partialName: String
        var bytes: Int64
        /// 0…1 from `com.apple.progress.fractionCompleted`, if the browser writes it.
        var fraction: Double?
        var isUnconfirmed: Bool
    }

    /// A file that isn't partial, for names the reducer is watching.
    struct Final: Equatable, Sendable {
        var size: Int64
        var modified: Date
    }

    var entries: [Entry]
    var finals: [String: Final]
}

/// Downloads: progress for browser downloads into `~/Downloads`, as one
/// activity, and a banner when they finish. The rules that are easy to get wrong:
///
/// - **Finished, cancelled or just renamed?** A download that stops being a
///   partial file is finished only if the final file exists with data written
///   *after* the download began (Firefox leaves an empty placeholder; an old
///   file of the same name doesn't count). Otherwise it gets two seconds for
///   the rename to show up, and then it's treated as cancelled, quietly.
/// - **Chrome's "Unconfirmed" download carries on under its real name**; it is
///   one download, not one cancelled and one new.
/// - **Bounded:** at most 20 are tracked however many files appear.
/// - **Sleep:** a long gap between looks gives no speed (no spike) and no cancel.
/// - **Quiet announcements:** downloads that finish in one look share one
///   banner, and no more than three a minute.
/// - **Already in progress at launch** shows, with no announcement.
///
/// Foundation only: the watcher turns the folder into scans.
struct DownloadsReducer: Sendable {
    static let maxTracked = 20
    /// How long a vanished partial file waits for its final name to appear.
    static let vanishGrace: TimeInterval = 2
    /// No progress for this long and the activity goes stale.
    static let staleAfter: TimeInterval = 60
    /// Longer than this between looks (sleep) and speed isn't computed.
    static let longestSample: TimeInterval = 30

    struct Model: Equatable, Sendable {
        struct Item: Equatable, Sendable {
            var key: String
            var name: String
            var bytes: Int64
            var fraction: Double?
            /// Bytes a second, smoothed; nil until it can be measured.
            var speed: Double?
        }

        var items: [Item]
        /// Combined progress 0…1, or nil if any download's total is unknown.
        var overall: Double?
    }

    enum Event: Equatable, Sendable {
        case scan(DownloadsScan)
        /// The wake the reducer asked for.
        case tick
        /// The Mac woke: the last sample is too old to measure speed from.
        case wake
    }

    enum Effect: Equatable, Sendable {
        case post(Model, staleDate: Date)
        case end
        /// The names that just finished, sorted.
        case completed([String])
        case schedule(Date?)
    }

    private struct Item {
        var key: String
        var name: String
        var partialName: String
        var isUnconfirmed: Bool
        var startedAt: Date
        var bytes: Int64
        var fraction: Double?
        var speed: Double?
        var lastSample: Date?
        var lastChange: Date
        var vanishedAt: Date?
    }

    private var items: [String: Item] = [:]
    private var posted: (model: Model, stale: Date)?
    private var scheduled: Date?
    private var bannerLimit = RateLimit(minimumInterval: 0, maxPerWindow: 3, window: 60)

    /// The finished names worth looking for in the next scan.
    var watchedNames: Set<String> {
        Set(items.values.filter { !$0.isUnconfirmed }.map(\.key))
    }

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        var completed: [String] = []
        switch event {
        case .scan(let scan):
            completed = apply(scan, now: now)
        case .tick:
            break
        case .wake:
            for key in items.keys {
                items[key]?.lastSample = nil
                items[key]?.speed = nil
            }
        }
        // Cancelled: no final name turned up in time.
        for (key, item) in items {
            if let vanished = item.vanishedAt, now.timeIntervalSince(vanished) >= Self.vanishGrace - 0.001 {
                items[key] = nil
            }
        }
        return effects(completed: completed, now: now)
    }

    private mutating func apply(_ scan: DownloadsScan, now: Date) -> [String] {
        let present = Dictionary(scan.entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        // Chrome renames "Unconfirmed 1.crdownload" to its real name mid-download.
        for entry in scan.entries where items[entry.key] == nil {
            let candidates = items.values.filter { $0.isUnconfirmed && present[$0.key] == nil && $0.bytes <= entry.bytes }
            if let old = candidates.max(by: { $0.bytes < $1.bytes }) {
                var moved = old
                moved.key = entry.key
                moved.name = entry.name
                moved.partialName = entry.partialName
                moved.isUnconfirmed = entry.isUnconfirmed
                items[old.key] = nil
                items[entry.key] = moved
            }
        }

        for entry in scan.entries {
            if var item = items[entry.key] {
                if let last = item.lastSample {
                    let elapsed = now.timeIntervalSince(last)
                    if elapsed > 0, elapsed <= Self.longestSample, entry.bytes >= item.bytes {
                        let sample = Double(entry.bytes - item.bytes) / elapsed
                        item.speed = item.speed.map { 0.4 * sample + 0.6 * $0 } ?? sample
                    } else if elapsed > Self.longestSample {
                        item.speed = nil
                    }
                }
                if entry.bytes != item.bytes { item.lastChange = now }
                item.bytes = entry.bytes
                item.fraction = entry.fraction ?? item.fraction
                item.name = entry.name
                item.partialName = entry.partialName
                item.lastSample = now
                item.vanishedAt = nil
                items[entry.key] = item
            } else if items.count < Self.maxTracked {
                items[entry.key] = Item(key: entry.key, name: entry.name, partialName: entry.partialName,
                                        isUnconfirmed: entry.isUnconfirmed, startedAt: now, bytes: entry.bytes,
                                        fraction: entry.fraction, speed: nil, lastSample: now, lastChange: now, vanishedAt: nil)
            }
        }

        var finished: [String] = []
        for (key, item) in items where present[key] == nil {
            if !item.isUnconfirmed, let final = scan.finals[key], final.size > 0,
               final.modified >= item.startedAt.addingTimeInterval(-2) {
                items[key] = nil
                finished.append(item.name)
            } else if item.vanishedAt == nil {
                items[key]?.vanishedAt = now
            }
        }
        return finished.sorted()
    }

    private mutating func effects(completed: [String], now: Date) -> [Effect] {
        var result: [Effect] = []
        let active = items.values.filter { $0.vanishedAt == nil }.sorted { ($0.startedAt, $0.key) < ($1.startedAt, $1.key) }
        if active.isEmpty {
            if posted != nil {
                posted = nil
                result.append(.end)
            }
        } else {
            let model = Model(
                items: active.map { Model.Item(key: $0.key, name: $0.name, bytes: $0.bytes, fraction: $0.fraction, speed: $0.speed) },
                overall: Self.overall(active)
            )
            let stale = (active.map(\.lastChange).max() ?? now).addingTimeInterval(Self.staleAfter)
            if posted?.model != model || posted?.stale != stale {
                posted = (model, stale)
                result.append(.post(model, staleDate: stale))
            }
        }
        if !completed.isEmpty, bannerLimit.allow(at: now) {
            result.append(.completed(completed))
        }
        let next = items.values.compactMap { $0.vanishedAt?.addingTimeInterval(Self.vanishGrace) }.min()
        if next != scheduled {
            scheduled = next
            result.append(.schedule(next))
        }
        return result
    }

    /// Bytes so far over the estimated total, if every download shows progress.
    private static func overall(_ active: [Item]) -> Double? {
        var bytes = 0.0
        var total = 0.0
        for item in active {
            guard let fraction = item.fraction, fraction > 0 else { return nil }
            bytes += Double(item.bytes)
            total += Double(item.bytes) / fraction
        }
        return total > 0 ? min(bytes / total, 1) : nil
    }
}
