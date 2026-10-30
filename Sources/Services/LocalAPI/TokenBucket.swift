// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A token bucket: `burst` requests at once, refilling at `perSecond`. Pure.
struct TokenBucket: Sendable {
    let burst: Double
    let perSecond: Double
    private var tokens: Double
    private var last: Date?

    init(burst: Double, perSecond: Double) {
        self.burst = burst
        self.perSecond = perSecond
        tokens = burst
    }

    /// Nil if the request may go ahead (and is counted); otherwise how many
    /// seconds to wait.
    mutating func take(at now: Date) -> TimeInterval? {
        if let last { tokens = min(burst, tokens + max(0, now.timeIntervalSince(last)) * perSecond) }
        last = now
        if tokens >= 1 {
            tokens -= 1
            return nil
        }
        return (1 - tokens) / perSecond
    }
}

/// Counts failures in a sliding window and says when to stop answering bad
/// tokens. Pure.
struct FailureLimiter: Sendable {
    let maxFailures: Int
    let window: TimeInterval
    private var failures: [Date] = []

    init(maxFailures: Int, window: TimeInterval) {
        self.maxFailures = maxFailures
        self.window = window
    }

    mutating func isBlocked(at now: Date) -> Bool {
        failures.removeAll { now.timeIntervalSince($0) >= window }
        return failures.count >= maxFailures
    }

    mutating func recordFailure(at now: Date) {
        failures.removeAll { now.timeIntervalSince($0) >= window }
        failures.append(now)
    }
}
