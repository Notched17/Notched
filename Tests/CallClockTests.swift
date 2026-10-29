// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// A call's compact duration: seconds for the first minute, then whole minutes,
/// so a long call isn't redrawn every second (it cost about 0.6% CPU).
@Suite("CallClock")
struct CallClockTests {
    let start = Date(timeIntervalSinceReferenceDate: 90_000)

    @Test("The first minute shows m:ss, then whole minutes")
    func compactText() {
        #expect(CallClock.compactText(elapsed: 0) == "0:00")
        #expect(CallClock.compactText(elapsed: 7.9) == "0:07")
        #expect(CallClock.compactText(elapsed: 59.9) == "0:59")
        #expect(CallClock.compactText(elapsed: 60) == "1 min")
        #expect(CallClock.compactText(elapsed: 125) == "2 min")
        #expect(CallClock.compactText(elapsed: 3_600) == "60 min")
        #expect(CallClock.compactText(elapsed: 7_500) == "125 min")
    }

    @Test("A negative elapsed time (a clock change) reads as the start")
    func negativeElapsed() {
        #expect(CallClock.compactText(elapsed: -5) == "0:00")
    }

    @Test("Ticks come every second in the first minute, then every minute on the minute")
    func nextTick() {
        #expect(CallClock.nextTick(startedAt: start, after: start) == start.addingTimeInterval(1))
        #expect(CallClock.nextTick(startedAt: start, after: start.addingTimeInterval(7.2)) == start.addingTimeInterval(8))
        #expect(CallClock.nextTick(startedAt: start, after: start.addingTimeInterval(58.5)) == start.addingTimeInterval(59))
        #expect(CallClock.nextTick(startedAt: start, after: start.addingTimeInterval(59)) == start.addingTimeInterval(60))
        #expect(CallClock.nextTick(startedAt: start, after: start.addingTimeInterval(60)) == start.addingTimeInterval(120))
        #expect(CallClock.nextTick(startedAt: start, after: start.addingTimeInterval(61)) == start.addingTimeInterval(120))
        #expect(CallClock.nextTick(startedAt: start, after: start.addingTimeInterval(3_599)) == start.addingTimeInterval(3_600))
    }

    @Test("A tick is always in the future, so the schedule can't spin")
    func ticksAdvance() {
        var date = start.addingTimeInterval(-3)
        for _ in 0..<500 {
            let next = CallClock.nextTick(startedAt: start, after: date)
            #expect(next > date)
            date = next
        }
    }

    @Test("Before the start (a clock change) the next tick is the start")
    func beforeStart() {
        #expect(CallClock.nextTick(startedAt: start, after: start.addingTimeInterval(-30)) == start.addingTimeInterval(1))
    }
}
