// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import DynamicNotch

@Suite("RefreshPlan")
struct RefreshPlanTests {
    let start = Date(timeIntervalSinceReferenceDate: 10_000)

    private func entry(
        _ id: Int,
        every seconds: Double,
        tolerance: Double = 0.1,
        when condition: RefreshCondition = .always,
        lastFired: Date? = nil
    ) -> RefreshEntry {
        RefreshEntry(
            id: RefreshToken(rawValue: id), interval: seconds, tolerance: tolerance,
            condition: condition, registeredAt: start, lastFired: lastFired
        )
    }

    private var awake: RefreshContext { RefreshContext() }

    @Test("A new entry first fires one interval after it was registered")
    func firstFire() {
        let deadline = RefreshPlan.nextDeadline([entry(1, every: 2)], context: awake)
        #expect(deadline?.date == start + 2)
    }

    @Test("The next deadline is the earliest across entries")
    func earliestDeadline() {
        let entries = [entry(1, every: 30), entry(2, every: 2, lastFired: start + 5), entry(3, every: 10)]
        #expect(RefreshPlan.nextDeadline(entries, context: awake)?.date == start + 7)
    }

    @Test("Tolerance is at least 10% of the interval, so the system can coalesce wake-ups")
    func minimumTolerance() {
        let deadline = RefreshPlan.nextDeadline([entry(1, every: 10, tolerance: 0)], context: awake)
        #expect(deadline?.leeway == 1)
        let generous = RefreshPlan.nextDeadline([entry(1, every: 10, tolerance: 0.25)], context: awake)
        #expect(generous?.leeway == 2.5)
    }

    @Test("On battery intervals double; in Low Power Mode they quadruple")
    func powerMultipliers() {
        var context = awake
        context.power = .battery
        #expect(RefreshPlan.nextDeadline([entry(1, every: 2)], context: context)?.date == start + 4)
        context.power = .lowPower
        #expect(RefreshPlan.nextDeadline([entry(1, every: 2)], context: context)?.date == start + 8)
    }

    @Test("Nothing runs while the screens are asleep or locked")
    func suspended() {
        var context = awake
        context.suspended = true
        #expect(RefreshPlan.nextDeadline([entry(1, every: 2)], context: context) == nil)
        #expect(RefreshPlan.due([entry(1, every: 2)], at: start + 100, context: context).isEmpty)
    }

    @Test("Visibility conditions pause work for UI that isn't on screen")
    func visibilityConditions() {
        let entries = [
            entry(1, every: 2, when: .whileUIVisible("permissions")),
            entry(2, every: 2, when: .whileIslandVisible),
            entry(3, every: 2, when: .whileExpanded),
        ]
        var context = awake
        context.islandVisible = false
        #expect(RefreshPlan.nextDeadline(entries, context: context) == nil)

        context.visibleUI = ["permissions"]
        #expect(RefreshPlan.due(entries, at: start + 2, context: context).map(\.rawValue) == [1])

        context.islandVisible = true
        #expect(RefreshPlan.due(entries, at: start + 2, context: context).map(\.rawValue) == [1, 2])

        context.islandExpanded = true
        #expect(RefreshPlan.due(entries, at: start + 2, context: context).map(\.rawValue) == [1, 2, 3])
    }

    @Test("Entries due within their tolerance fire together in one wake-up")
    func coalescing() {
        let entries = [entry(1, every: 10), entry(2, every: 10.5), entry(3, every: 30)]
        // At t = 10, entry 2 is due in 0.5 s, within its 1.05 s tolerance, so it runs now too.
        #expect(RefreshPlan.due(entries, at: start + 10, context: awake).map(\.rawValue) == [1, 2])
    }

    @Test("Nothing is due before its time")
    func notDueEarly() {
        #expect(RefreshPlan.due([entry(1, every: 10)], at: start + 5, context: awake).isEmpty)
    }
}
