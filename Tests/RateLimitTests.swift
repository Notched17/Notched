// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("RateLimit and WakeQuiet")
struct RateLimitTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 70_000)

    @Test("Links can't start timers faster than every 2 s, or more than 5 a minute")
    func linkLimit() {
        var sut = RateLimit(minimumInterval: 2, maxPerWindow: 5, window: 60)
        let allowed = [0.0, 1, 2, 4, 6, 8, 10, 59, 60].map { sut.allow(at: t0 + $0) }
        #expect(allowed == [true, false, true, true, true, true, false, false, true])
    }

    @Test("Refused attempts don't count towards the limit")
    func refusedDontCount() {
        var sut = RateLimit(minimumInterval: 60, maxPerWindow: 1, window: 60)
        let first = sut.allow(at: t0)
        let during = (1..<60).map { sut.allow(at: t0 + TimeInterval($0)) }
        let after = sut.allow(at: t0 + 60)
        #expect(first)
        #expect(!during.contains(true))
        #expect(after)
    }

    @Test("Quiet while asleep and for a few seconds after waking")
    func wakeQuiet() {
        var sut = WakeQuiet()
        #expect(!sut.isQuiet(at: t0))
        sut.willSleep()
        #expect(sut.isQuiet(at: t0 + 3600))
        sut.didWake(at: t0 + 3600)
        #expect(sut.isQuiet(at: t0 + 3600 + WakeQuiet.afterWake - 0.1))
        #expect(!sut.isQuiet(at: t0 + 3600 + WakeQuiet.afterWake))
    }
}
