// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import Testing
@testable import DynamicNotch

@Suite("ActivityCoordinator")
@MainActor
struct ActivityCoordinatorTests {
    /// A clock the tests move by hand.
    final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    let clock = TestClock()

    private func makeCoordinator() -> (ActivityCoordinator, WakeLog) {
        let log = WakeLog()
        let clock = self.clock
        let coordinator = ActivityCoordinator(now: { clock.now }, scheduleWake: { log.dates.append($0) })
        return (coordinator, log)
    }

    final class WakeLog { var dates: [Date?] = [] }

    private func content(_ label: String, width: CGFloat = 24) -> ActivityContent {
        ActivityContent(width: width, accessibilityLabel: label) { Text(label) }
    }

    private func activity(
        _ id: ActivityID,
        module: ModuleID = "test",
        priority: ActivityPriority,
        lifetime: ActivityLifetime = .untilRemoved,
        leading: String? = nil,
        trailing: String? = nil
    ) -> Activity {
        Activity(
            id: id, moduleID: module, priority: priority, lifetime: lifetime,
            compactLeading: leading.map { content($0) },
            compactTrailing: trailing.map { content($0) },
            expanded: content("\(id.rawValue) expanded")
        )
    }

    // MARK: Ranking

    @Test("With nothing live, both compact slots are empty")
    func empty() {
        let (sut, _) = makeCoordinator()
        #expect(sut.leading == nil)
        #expect(sut.trailing == nil)
        #expect(sut.ranked.isEmpty)
    }

    @Test("Activities rank by priority: alerts, then live sessions, then media")
    func rankByPriority() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("media", priority: .media))
        sut.post(activity("alert", priority: .alert))
        sut.post(activity("timer", priority: .liveSession))
        #expect(sut.ranked.map(\.id) == ["alert", "timer", "media"])
    }

    @Test("Within a priority, the newest activity ranks first")
    func newestFirstWithinPriority() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("older", priority: .liveSession))
        clock.advance(1)
        sut.post(activity("newer", priority: .liveSession))
        #expect(sut.ranked.map(\.id) == ["newer", "older"])
    }

    // MARK: Compact slots

    @Test("An alert at the top owns both compact slots, even one it leaves empty")
    func alertOwnsBothSlots() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("media", priority: .media, leading: "art", trailing: "bars"))
        sut.post(activity("battery", priority: .alert, leading: "bolt"))
        #expect(sut.leading?.activityID == "battery")
        #expect(sut.trailing == nil)
    }

    @Test("Without an alert, each slot comes from the highest-ranked activity that fills it")
    func slotsShareAcrossActivities() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("media", priority: .media, leading: "art", trailing: "bars"))
        sut.post(activity("timer", priority: .liveSession, trailing: "12:00"))
        #expect(sut.leading?.activityID == "media")
        #expect(sut.trailing?.activityID == "timer")
    }

    // MARK: Transient alerts

    @Test("When a transient alert expires, the island returns to what it showed before")
    func expiryRestoresPreviousState() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("timer", priority: .liveSession, leading: "timer", trailing: "12:00"))
        sut.post(activity("caps", priority: .alert, lifetime: .transient(.seconds(2)), leading: "capslock"))
        #expect(sut.leading?.activityID == "caps")
        clock.advance(2)
        sut.expire(at: clock.now)
        #expect(sut.leading?.activityID == "timer")
        #expect(sut.trailing?.activityID == "timer")
        #expect(sut.ranked.map(\.id) == ["timer"])
    }

    @Test("A transient alert stays until its expiry time")
    func notExpiredEarly() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("caps", priority: .alert, lifetime: .transient(.seconds(2)), leading: "capslock"))
        clock.advance(1.9)
        sut.expire(at: clock.now)
        #expect(sut.leading?.activityID == "caps")
    }

    @Test("The next expiry is the earliest transient expiry, and is reported to the wake scheduler")
    func nextExpiry() {
        let (sut, wakes) = makeCoordinator()
        #expect(sut.nextExpiry == nil)
        sut.post(activity("a", priority: .alert, lifetime: .transient(.seconds(5))))
        sut.post(activity("b", priority: .alert, lifetime: .transient(.seconds(3))))
        sut.post(activity("c", priority: .liveSession))
        let expected = clock.now + 3
        #expect(sut.nextExpiry == expected)
        #expect(wakes.dates.last == expected)
    }

    @Test("Re-posting a transient activity resets its expiry")
    func repostResetsExpiry() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("volume", priority: .alert, lifetime: .transient(.seconds(2))))
        clock.advance(1.5)
        sut.post(activity("volume", priority: .alert, lifetime: .transient(.seconds(2))))
        clock.advance(1)
        sut.expire(at: clock.now)
        #expect(sut.ranked.map(\.id) == ["volume"])
    }

    // MARK: Updates and removal

    @Test("Posting an existing id updates it in place instead of adding a second entry")
    func updateInPlace() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("timer", priority: .liveSession, trailing: "12:00"))
        clock.advance(1)
        sut.post(activity("other", priority: .liveSession))
        clock.advance(1)
        sut.post(activity("timer", priority: .liveSession, trailing: "11:59"))
        #expect(sut.ranked.map(\.id) == ["other", "timer"])
        #expect(sut.trailing?.content.accessibilityLabel == "11:59")
    }

    @Test("Removing an activity clears its slots")
    func remove() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("timer", priority: .liveSession, leading: "timer"))
        sut.remove("timer")
        #expect(sut.leading == nil)
        #expect(sut.ranked.isEmpty)
    }

    @Test("Removing a module's activities leaves other modules' activities alone")
    func removeAllFromModule() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("a1", module: "a", priority: .liveSession))
        sut.post(activity("a2", module: "a", priority: .alert))
        sut.post(activity("b1", module: "b", priority: .media))
        sut.removeAll(from: "a")
        #expect(sut.ranked.map(\.id) == ["b1"])
    }

    // MARK: Alert bounce

    @Test("A new alert bumps the alert serial; updates and other priorities don't")
    func alertSerial() {
        let (sut, _) = makeCoordinator()
        sut.post(activity("timer", priority: .liveSession))
        #expect(sut.alertSerial == 0)
        sut.post(activity("caps", priority: .alert, lifetime: .transient(.seconds(2))))
        #expect(sut.alertSerial == 1)
        sut.post(activity("caps", priority: .alert, lifetime: .transient(.seconds(2))))
        #expect(sut.alertSerial == 1)
        sut.post(activity("battery", priority: .alert))
        #expect(sut.alertSerial == 2)
    }
}
