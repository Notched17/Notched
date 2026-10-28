// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Allows something at most `maxPerWindow` times per `window`, and never
/// twice within `minimumInterval`. Pure, so the limits are tested. Used for
/// `notched://` links, which any app or web page can open.
struct RateLimit: Sendable {
    let minimumInterval: TimeInterval
    let maxPerWindow: Int
    let window: TimeInterval
    private var recent: [Date] = []

    init(minimumInterval: TimeInterval, maxPerWindow: Int, window: TimeInterval) {
        self.minimumInterval = minimumInterval
        self.maxPerWindow = maxPerWindow
        self.window = window
    }

    /// True (and counted) if it may happen now.
    mutating func allow(at now: Date) -> Bool {
        recent.removeAll { now.timeIntervalSince($0) >= window }
        if let last = recent.last, now.timeIntervalSince(last) < minimumInterval { return false }
        guard recent.count < maxPerWindow else { return false }
        recent.append(now)
        return true
    }
}

/// Quiet for a moment around sleep: devices and networks reconnect as the
/// Mac wakes, and that isn't news. Pure.
struct WakeQuiet: Sendable {
    static let afterWake: TimeInterval = 8

    private var isAsleep = false
    private var quietUntil: Date?

    mutating func willSleep() {
        isAsleep = true
    }

    mutating func didWake(at now: Date) {
        isAsleep = false
        quietUntil = now.addingTimeInterval(Self.afterWake)
    }

    func isQuiet(at now: Date) -> Bool {
        isAsleep || quietUntil.map { now < $0 } ?? false
    }
}
