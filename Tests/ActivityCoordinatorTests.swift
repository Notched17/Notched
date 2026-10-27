// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import Testing
@testable import Notched

/// Scenario tests for the iPhone-parity activity rules (ADR-0006,
/// ISLAND-BEHAVIOR.md §1–§2).
@Suite("ActivityCoordinator")
@MainActor
struct ActivityCoordinatorTests {
    /// A clock the tests move by hand.
    final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    final class WakeLog { var dates: [Date?] = [] }

    let clock = TestClock()
    let wakes = WakeLog()

    private func makeCoordinator(_ configuration: ActivityCoordinator.Configuration = .init()) -> ActivityCoordinator {
        let clock = clock
        let wakes = wakes
        return ActivityCoordinator(configuration: configuration, now: { clock.now }, scheduleWake: { wakes.dates.append($0) })
    }

    /// Moves the clock and lets the coordinator handle whatever fell due,
    /// as the app's one-shot wake timer would.
    private func tick(_ sut: ActivityCoordinator, _ seconds: TimeInterval) {
        clock.advance(seconds)
        sut.advance(to: clock.now)
    }

    private func activity(
        _ id: ActivityID,
        module: ModuleID = "test",
        kind: ActivityKind = .live,
        relevance: Double = 0,
        hideable: Bool = true,
        staleDate: Date? = nil
    ) -> LiveActivity {
        LiveActivity(
            id: id, moduleID: module, kind: kind, title: id.rawValue, relevance: relevance, isHideable: hideable,
            staleDate: staleDate, accessibilityLabel: id.rawValue, presentation: .text(id.rawValue)
        )
    }

    private func banner(_ id: String, module: ModuleID = "test") -> TransientBanner {
        TransientBanner(id: id, moduleID: module, leading: IslandRegion { Text(id) }, accessibilityLabel: id)
    }

    private func ids(_ records: [ActivityRecord]) -> [ActivityID] { records.map(\.id) }

    // MARK: Ranking

    @Test("Activities rank by class: system, then live, then media, then passive")
    func rankByClass() {
        let sut = makeCoordinator()
        sut.post(activity("p", kind: .passive))
        sut.post(activity("m", kind: .media))
        sut.post(activity("l", kind: .live))
        sut.post(activity("s", kind: .system))
        #expect(ids(sut.live) == ["s", "l", "m", "p"])
    }

    @Test("Within a class, higher relevance wins")
    func relevanceWithinClass() {
        let sut = makeCoordinator()
        sut.post(activity("low", relevance: 10))
        sut.post(activity("high", relevance: 50))
        #expect(ids(sut.live) == ["high", "low"])
    }

    @Test("On equal relevance the activity started first wins, so newcomers don't steal the island")
    func startOrderTiebreak() {
        let sut = makeCoordinator()
        sut.post(activity("first"))
        clock.advance(1)
        sut.post(activity("second"))
        #expect(ids(sut.live) == ["first", "second"])
        #expect(sut.primary?.id == "first")
    }

    @Test("An update in place keeps its start order and bumps its revision")
    func updateKeepsStartOrder() {
        let sut = makeCoordinator()
        sut.post(activity("first"))
        sut.post(activity("second"))
        sut.post(activity("first"))
        #expect(ids(sut.live) == ["first", "second"])
        #expect(sut.live.first?.revision == 1)
    }

    @Test("Relevance can change with an update, and the ranking follows")
    func relevanceChangesWithUpdate() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.post(activity("b", relevance: 5))
        #expect(ids(sut.live) == ["b", "a"])
    }

    // MARK: Primary and minimal

    @Test("One activity is the primary and there are no minimal bubbles")
    func oneActivity() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        #expect(sut.primary?.id == "a")
        #expect(sut.minimal.isEmpty)
    }

    @Test("Two activities: the higher class is primary, the other is a minimal bubble")
    func twoActivities() {
        let sut = makeCoordinator()
        sut.post(activity("music", kind: .media))
        sut.post(activity("timer", kind: .live))
        #expect(sut.primary?.id == "timer")
        #expect(ids(sut.minimal) == ["music"])
    }

    @Test("Three activities: primary, then the trailing bubble, then the leading bubble")
    func threeActivities() {
        let sut = makeCoordinator()
        sut.post(activity("music", kind: .media))
        sut.post(activity("timer", kind: .live))
        sut.post(activity("call", kind: .system))
        #expect(sut.primary?.id == "call")
        #expect(ids(sut.minimal) == ["timer", "music"])
    }

    // MARK: Cap of three

    @Test("Four activities: three are visible on the island, the fourth is only listed")
    func fourActivities() {
        let sut = makeCoordinator()
        for id in ["a", "b", "c", "d"] { sut.post(activity(ActivityID(id))) }
        #expect(sut.primary?.id == "a")
        #expect(ids(sut.minimal) == ["b", "c"])
        #expect(ids(sut.listedOnly) == ["d"])
        #expect(ids(sut.visible) == ["a", "b", "c", "d"])
    }

    @Test("When a visible activity ends, the listed one moves onto the island")
    func listedMovesUp() {
        let sut = makeCoordinator()
        for id in ["a", "b", "c", "d"] { sut.post(activity(ActivityID(id))) }
        sut.end("b")
        #expect(ids(sut.minimal) == ["c", "d"])
        #expect(sut.listedOnly.isEmpty)
    }

    // MARK: Swap

    @Test("Making a minimal activity primary swaps them")
    func makePrimarySwaps() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.makePrimary("b")
        #expect(sut.primary?.id == "b")
        #expect(ids(sut.minimal) == ["a"])
    }

    @Test("A swap is sticky across updates and newer activities of a lower or equal class")
    func swapIsSticky() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.makePrimary("b")
        sut.post(activity("a", relevance: 99))
        sut.post(activity("c"))
        #expect(sut.primary?.id == "b")
    }

    @Test("A swap clears when the demoted activity ends, and the natural ranking returns")
    func swapClearsWhenDemotedEnds() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.post(activity("c"))
        sut.makePrimary("c")
        sut.end("a")
        #expect(sut.primary?.id == "b")
    }

    @Test("A swap clears when the promoted activity ends")
    func swapClearsWhenPromotedEnds() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.post(activity("c"))
        sut.makePrimary("c")
        sut.end("c")
        #expect(sut.primary?.id == "a")
    }

    @Test("A new system activity clears the swap")
    func newSystemClearsSwap() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.makePrimary("b")
        sut.post(activity("call", kind: .system))
        #expect(sut.primary?.id == "call")
        sut.end("call")
        #expect(sut.primary?.id == "a")
    }

    @Test("Cycling walks the visible activities in rank order and wraps around")
    func cyclePrimary() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.post(activity("c"))
        sut.cyclePrimary(forward: true)
        #expect(sut.primary?.id == "b")
        sut.cyclePrimary(forward: true)
        #expect(sut.primary?.id == "c")
        sut.cyclePrimary(forward: true)
        #expect(sut.primary?.id == "a")
        sut.cyclePrimary(forward: false)
        #expect(sut.primary?.id == "c")
    }

    // MARK: Hide

    @Test("Hiding takes an activity off the island but keeps it listed and updating")
    func hideKeepsActivity() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.hide("b")
        #expect(ids(sut.visible) == ["a"])
        #expect(sut.minimal.isEmpty)
        #expect(ids(sut.hidden) == ["b"])
        sut.post(activity("b"))
        #expect(ids(sut.hidden) == ["b"])
        #expect(sut.hidden.first?.revision == 1)
    }

    @Test("An activity that isn't hideable ignores hide")
    func nonHideableIgnoresHide() {
        let sut = makeCoordinator()
        sut.post(activity("call", kind: .system, hideable: false))
        sut.hide("call")
        #expect(sut.primary?.id == "call")
        #expect(sut.hidden.isEmpty)
    }

    @Test("Hiding the primary promotes the next activity")
    func hidePrimaryPromotesNext() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.hide("a")
        #expect(sut.primary?.id == "b")
    }

    @Test("Unhiding restores an activity at its rank")
    func unhideRestoresRank() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.hide("a")
        sut.unhide("a")
        #expect(sut.primary?.id == "a")
        #expect(sut.hidden.isEmpty)
    }

    // MARK: Stale

    @Test("Past its stale date an activity turns stale, with a wake scheduled for that moment")
    func staleDate() {
        let sut = makeCoordinator()
        let staleAt = clock.now + 10
        sut.post(activity("a", staleDate: staleAt))
        #expect(sut.primary?.state == .active)
        #expect(wakes.dates.last == staleAt)
        tick(sut, 10)
        #expect(sut.primary?.state == .stale)
    }

    @Test("An update with a later stale date makes a stale activity active again")
    func updateRefreshesStale() {
        let sut = makeCoordinator()
        sut.post(activity("a", staleDate: clock.now + 1))
        tick(sut, 2)
        sut.post(activity("a", staleDate: clock.now + 60))
        #expect(sut.primary?.state == .active)
    }

    // MARK: Ended and Recent

    @Test("Ending takes an activity off the island at once and lists it under Recent for the retention time")
    func endMovesToRecent() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.end("a")
        #expect(sut.live.isEmpty)
        #expect(sut.primary == nil)
        #expect(ids(sut.recent) == ["a"])
        #expect(sut.recent.first?.state == .ended(dismissAt: clock.now + 15 * 60))
    }

    @Test("Immediate dismissal skips Recent")
    func immediateDismissal() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.end("a", dismissal: .immediate)
        #expect(sut.recent.isEmpty)
    }

    @Test("A dismissal date is capped at four hours")
    func dismissalCapped() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.end("a", dismissal: .after(clock.now + 10 * 3600))
        #expect(sut.recent.first?.state == .ended(dismissAt: clock.now + 4 * 3600))
    }

    @Test("A Recent entry disappears at its dismissal time")
    func recentExpires() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.end("a")
        tick(sut, 15 * 60 - 1)
        #expect(ids(sut.recent) == ["a"])
        tick(sut, 1)
        #expect(sut.recent.isEmpty)
    }

    @Test("A hidden activity that ends moves to Recent too")
    func hiddenEndsToRecent() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.hide("a")
        sut.end("a")
        #expect(sut.hidden.isEmpty)
        #expect(ids(sut.recent) == ["a"])
    }

    @Test("Posting an ended id again starts it afresh and removes it from Recent")
    func repostEnded() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.end("a")
        sut.post(activity("a"))
        #expect(sut.recent.isEmpty)
        #expect(ids(sut.live) == ["b", "a"])
    }

    @Test("Ending a module's activities leaves other modules alone and skips Recent")
    func endAllFromModule() {
        let sut = makeCoordinator()
        sut.post(activity("x1", module: "x"))
        sut.post(activity("y1", module: "y"))
        sut.show(banner("x-banner", module: "x"))
        sut.endAll(from: "x")
        #expect(ids(sut.live) == ["y1"])
        #expect(sut.recent.isEmpty)
        #expect(sut.banner == nil)
    }

    // MARK: Alert expansion

    @Test("An alerting update expands that activity for the alert duration, then the island returns")
    func alertExpands() {
        let sut = makeCoordinator()
        sut.post(activity("timer"), alert: AlertRequest(duration: .seconds(3), sound: "Glass"))
        #expect(sut.alert?.activityID == "timer")
        #expect(sut.alert?.endsAt == clock.now + 3)
        #expect(sut.alert?.sound == "Glass")
        tick(sut, 3)
        #expect(sut.alert == nil)
        #expect(sut.primary?.id == "timer")
    }

    @Test("Without a duration, an alert uses the configured one")
    func alertDefaultDuration() {
        let sut = makeCoordinator()
        sut.post(activity("timer"), alert: AlertRequest())
        #expect(sut.alert?.endsAt == clock.now + 4)
    }

    @Test("A new system activity alerts by default; its updates don't")
    func newSystemAlerts() {
        let sut = makeCoordinator()
        sut.post(activity("call", kind: .system))
        #expect(sut.alert?.activityID == "call")
        tick(sut, 4)
        sut.post(activity("call", kind: .system))
        #expect(sut.alert == nil)
    }

    @Test("Two alerts at once are shown one after the other")
    func alertsQueue() {
        let sut = makeCoordinator()
        sut.post(activity("a"), alert: AlertRequest())
        sut.post(activity("b"), alert: AlertRequest())
        #expect(sut.alert?.activityID == "a")
        tick(sut, 4)
        #expect(sut.alert?.activityID == "b")
        #expect(sut.alert?.endsAt == clock.now + 4)
        tick(sut, 4)
        #expect(sut.alert == nil)
    }

    @Test("Alerting a queued activity again replaces its queue entry")
    func realertReplacesQueued() {
        let sut = makeCoordinator()
        sut.post(activity("a"), alert: AlertRequest())
        sut.post(activity("b"), alert: AlertRequest(duration: .seconds(2)))
        sut.post(activity("b"), alert: AlertRequest(duration: .seconds(6)))
        tick(sut, 4)
        #expect(sut.alert?.endsAt == clock.now + 6)
        tick(sut, 6)
        #expect(sut.alert == nil)
    }

    @Test("While the user is on the island, alerts wait, and their time starts when they show")
    func alertsWaitWhileInteracting() {
        let sut = makeCoordinator()
        sut.isInteracting = true
        sut.post(activity("a"), alert: AlertRequest())
        #expect(sut.alert == nil)
        tick(sut, 10)
        sut.isInteracting = false
        #expect(sut.alert?.activityID == "a")
        #expect(sut.alert?.endsAt == clock.now + 4)
    }

    @Test("When the pointer takes over an alert, it ends without starting the next one")
    func userTakesOverAlert() {
        let sut = makeCoordinator()
        sut.post(activity("a"), alert: AlertRequest())
        sut.post(activity("b"), alert: AlertRequest())
        sut.isInteracting = true
        sut.userTookOverAlert()
        #expect(sut.alert == nil)
        sut.isInteracting = false
        #expect(sut.alert?.activityID == "b")
    }

    @Test("Ending an activity drops its alert, queued or showing")
    func endedActivityAlertDropped() {
        let sut = makeCoordinator()
        sut.post(activity("a"), alert: AlertRequest())
        sut.post(activity("b"), alert: AlertRequest())
        sut.end("b")
        sut.end("a")
        #expect(sut.alert == nil)
        tick(sut, 4)
        #expect(sut.alert == nil)
    }

    @Test("With alert expansion off, an alert bounces the island instead")
    func alertExpansionOff() {
        var configuration = ActivityCoordinator.Configuration()
        configuration.alertExpansionEnabled = false
        let sut = makeCoordinator(configuration)
        sut.post(activity("a"), alert: AlertRequest())
        #expect(sut.alert == nil)
        #expect(sut.bounceSerial == 1)
    }

    @Test("An alert on a hidden activity still expands it, and it stays hidden")
    func alertOnHidden() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.hide("a")
        sut.post(activity("a"), alert: AlertRequest())
        #expect(sut.alert?.activityID == "a")
        #expect(ids(sut.hidden) == ["a"])
    }

    // MARK: Transient banners

    @Test("A banner shows for the banner duration, then the island returns; it never takes a minimal slot")
    func bannerShowsThenRestores() {
        let sut = makeCoordinator()
        sut.post(activity("a"))
        sut.post(activity("b"))
        sut.show(banner("charging"))
        #expect(sut.banner?.id == "charging")
        #expect(sut.primary?.id == "a")
        #expect(ids(sut.minimal) == ["b"])
        tick(sut, 2)
        #expect(sut.banner == nil)
        #expect(ids(sut.minimal) == ["b"])
    }

    @Test("Showing the same banner again restarts its time without another bounce")
    func bannerSameIdExtends() {
        let sut = makeCoordinator()
        sut.show(banner("volume"))
        #expect(sut.bounceSerial == 1)
        tick(sut, 1.5)
        sut.show(banner("volume"))
        tick(sut, 1)
        #expect(sut.banner?.id == "volume")
        tick(sut, 1)
        #expect(sut.banner == nil)
        #expect(sut.bounceSerial == 1)
    }

    @Test("A banner during an alert waits for it, and the newest waiting banner wins")
    func bannerWaitsForAlert() {
        let sut = makeCoordinator()
        sut.post(activity("a"), alert: AlertRequest())
        sut.show(banner("old"))
        sut.show(banner("new"))
        #expect(sut.banner == nil)
        tick(sut, 4)
        #expect(sut.banner?.id == "new")
        tick(sut, 2)
        #expect(sut.banner == nil)
    }

    @Test("A banner that waited more than five seconds is dropped")
    func staleBannerDropped() {
        let sut = makeCoordinator()
        sut.isInteracting = true
        sut.show(banner("charging"))
        tick(sut, 6)
        sut.isInteracting = false
        #expect(sut.banner == nil)
    }

    // MARK: Deadlines

    @Test("The next deadline is the earliest pending change, and it is reported for a single wake-up")
    func nextDeadline() {
        let sut = makeCoordinator()
        sut.post(activity("a"), alert: AlertRequest())
        sut.post(activity("b", staleDate: clock.now + 3))
        let expected = clock.now + 3
        #expect(sut.nextDeadline == expected)
        #expect(wakes.dates.last == expected)
    }
}

extension ActivityPresentation {
    /// A plain text presentation for tests.
    static func text(_ label: String) -> ActivityPresentation {
        ActivityPresentation(
            compactLeading: IslandRegion { Text(label) },
            compactTrailing: IslandRegion { Text(label) },
            minimal: IslandRegion { Text(label) },
            expanded: ExpandedPresentation(center: ExpandedRegion { Text(label) })
        )
    }
}
