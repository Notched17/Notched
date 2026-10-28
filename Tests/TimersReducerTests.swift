// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Countdown timers and the stopwatch (#37): date-based, survive sleep and relaunch.
@Suite("TimersReducer")
struct TimersReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 90_000)
    let tea = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let pasta = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    /// The effects that matter to a test (persisting happens after every change).
    private func visible(_ effects: [TimersReducer.Effect]) -> [TimersReducer.Effect] {
        effects.filter { if case .persist = $0 { false } else { true } }
    }

    private func running(_ id: UUID, label: String = "Timer", duration: TimeInterval, endsAt: Date) -> TimerItem {
        TimerItem(id: id, label: label, duration: duration, phase: .running(endsAt: endsAt))
    }

    // MARK: Running

    @Test("Starting a timer posts it and schedules its end; the state is persisted")
    func startPostsAndSchedules() {
        var sut = TimersReducer()
        let effects = sut.reduce(.start(duration: 600, label: "Tea", id: tea), now: t0)
        let item = running(tea, label: "Tea", duration: 600, endsAt: t0 + 600)
        #expect(visible(effects) == [.post(item), .schedule(t0 + 600)])
        #expect(effects.last == .persist(TimersState(timers: [item])))
    }

    @Test("With several timers the earliest end is scheduled")
    func earliestDeadlineScheduled() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 600, label: nil, id: tea), now: t0)
        #expect(visible(sut.reduce(.start(duration: 300, label: nil, id: pasta), now: t0)).last == .schedule(t0 + 300))
    }

    @Test("Pausing freezes the time left")
    func pauseFreezes() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 600, label: nil, id: tea), now: t0)
        let paused = TimerItem(id: tea, label: "Timer", duration: 600, phase: .paused(remaining: 540))
        #expect(visible(sut.reduce(.pause(tea), now: t0 + 60)) == [.post(paused), .schedule(nil)])
        #expect(paused.remaining(at: t0 + 5000) == 540)
    }

    @Test("Resuming counts down from where it was paused")
    func resumeRecomputesEnd() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 600, label: nil, id: tea), now: t0)
        _ = sut.reduce(.pause(tea), now: t0 + 60)
        let resumed = running(tea, duration: 600, endsAt: t0 + 600 + 540)
        #expect(visible(sut.reduce(.resume(tea), now: t0 + 600)) == [.post(resumed), .schedule(t0 + 1140)])
    }

    @Test("+1 min adds a minute, running or paused")
    func addMinute() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 600, label: nil, id: tea), now: t0)
        #expect(visible(sut.reduce(.addMinute(tea), now: t0 + 10)) == [.post(running(tea, duration: 660, endsAt: t0 + 660)), .schedule(t0 + 660)])
        _ = sut.reduce(.pause(tea), now: t0 + 60)
        let paused = TimerItem(id: tea, label: "Timer", duration: 720, phase: .paused(remaining: 660))
        #expect(visible(sut.reduce(.addMinute(tea), now: t0 + 70)) == [.post(paused), .schedule(nil)])
    }

    @Test("Cancelling takes the timer away without a Recent entry")
    func cancelEndsWithoutRecent() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 600, label: nil, id: tea), now: t0)
        #expect(visible(sut.reduce(.cancel(tea), now: t0 + 5)) == [.end(tea, toRecent: false), .schedule(nil)])
        #expect(sut.state.timers.isEmpty)
        #expect(sut.reduce(.cancel(tea), now: t0 + 6).isEmpty)
    }

    // MARK: Finishing

    @Test("At its end a timer alerts with sound, shows as done for the alert, then goes to Recent")
    func completionAlertsWithSoundThenEnds() {
        var sut = TimersReducer(doneHold: 4)
        _ = sut.reduce(.start(duration: 60, label: "Tea", id: tea), now: t0)
        let done = TimerItem(id: tea, label: "Tea", duration: 60, phase: .done(endedAt: t0 + 60, until: t0 + 64))
        #expect(visible(sut.reduce(.deadline, now: t0 + 60)) == [.alert(done, sound: true), .schedule(t0 + 64)])
        #expect(visible(sut.reduce(.deadline, now: t0 + 64)) == [.end(tea, toRecent: true), .schedule(nil)])
        #expect(sut.state.timers.isEmpty)
    }

    @Test("Waking a few minutes after the end alerts quietly")
    func wakeAfterSleepAlertsQuietly() {
        var sut = TimersReducer(doneHold: 4)
        _ = sut.reduce(.start(duration: 60, label: nil, id: tea), now: t0)
        let done = TimerItem(id: tea, label: "Timer", duration: 60, phase: .done(endedAt: t0 + 60, until: t0 + 360 + 4))
        #expect(visible(sut.reduce(.wake, now: t0 + 360)) == [.alert(done, sound: false), .schedule(t0 + 364)])
    }

    @Test("Waking long after the end skips the alert and lists it under Recent")
    func wakeLongAfterEndGoesToRecent() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 60, label: nil, id: tea), now: t0)
        let done = TimerItem(id: tea, label: "Timer", duration: 60, phase: .done(endedAt: t0 + 60, until: t0 + 3660))
        #expect(visible(sut.reduce(.wake, now: t0 + 3660)) == [.post(done), .end(tea, toRecent: true), .schedule(nil)])
    }

    @Test("Nothing due: a wake only reschedules")
    func wakeBeforeEnd() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 600, label: nil, id: tea), now: t0)
        #expect(visible(sut.reduce(.wake, now: t0 + 10)) == [.schedule(t0 + 600)])
    }

    // MARK: Relaunch

    @Test("After relaunch, running and paused timers carry on")
    func restoreResumesRunning() {
        var sut = TimersReducer()
        let item = running(tea, duration: 600, endsAt: t0 + 300)
        let paused = TimerItem(id: pasta, label: "Pasta", duration: 480, phase: .paused(remaining: 100))
        let saved = TimersState(timers: [item, paused], stopwatch: Stopwatch(startedAt: t0 - 10, accumulated: 5))
        #expect(visible(sut.reduce(.restore(saved), now: t0)) == [
            .post(item), .post(paused), .postStopwatch(Stopwatch(startedAt: t0 - 10, accumulated: 5)), .schedule(t0 + 300),
        ])
    }

    @Test("A timer that ended in the last ten minutes alerts once after relaunch, silently")
    func restoreRecentlyEndedAlertsSilently() {
        var sut = TimersReducer(doneHold: 4)
        let saved = TimersState(timers: [running(tea, duration: 60, endsAt: t0 - 120)])
        let done = TimerItem(id: tea, label: "Timer", duration: 60, phase: .done(endedAt: t0 - 120, until: t0 + 4))
        #expect(visible(sut.reduce(.restore(saved), now: t0)) == [.alert(done, sound: false), .schedule(t0 + 4)])
    }

    @Test("A timer that ended longer ago goes straight to Recent after relaunch")
    func restoreLongAgoGoesToRecent() {
        var sut = TimersReducer()
        let saved = TimersState(timers: [running(tea, duration: 60, endsAt: t0 - 3600)])
        let done = TimerItem(id: tea, label: "Timer", duration: 60, phase: .done(endedAt: t0 - 3600, until: t0))
        #expect(visible(sut.reduce(.restore(saved), now: t0)) == [.post(done), .end(tea, toRecent: true), .schedule(nil)])
    }

    @Test("The persisted state survives a JSON round trip")
    func stateIsCodable() throws {
        let state = TimersState(
            timers: [running(tea, label: "Tea", duration: 600, endsAt: t0),
                     TimerItem(id: pasta, label: "Pasta", duration: 60, phase: .paused(remaining: 30))],
            stopwatch: Stopwatch(startedAt: nil, accumulated: 12)
        )
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(TimersState.self, from: data) == state)
    }

    // MARK: Limits and labels

    @Test("At most ten timers run at once")
    func maxTenTimers() {
        var sut = TimersReducer()
        for index in 0..<10 { _ = sut.reduce(.start(duration: 60, label: nil, id: UUID()), now: t0 + Double(index)) }
        #expect(sut.reduce(.start(duration: 60, label: nil, id: tea), now: t0 + 20).isEmpty)
        #expect(sut.state.timers.count == 10)
    }

    @Test("Durations are kept between one second and a day")
    func durationClamped() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 0, label: nil, id: tea), now: t0)
        _ = sut.reduce(.start(duration: 1_000_000, label: nil, id: pasta), now: t0)
        #expect(sut.state.timers.map(\.duration) == [1, 86_400])
    }

    @Test("Labels are trimmed, cleaned and capped; no label means Timer")
    func labelCleaned() {
        #expect(TimersReducer.cleanLabel("  Green tea\n ") == "Green tea")
        #expect(TimersReducer.cleanLabel("Tea\u{0007}time") == "Teatime")
        #expect(TimersReducer.cleanLabel(String(repeating: "a", count: 60))?.count == 40)
        #expect(TimersReducer.cleanLabel("   ") == nil)
        #expect(TimersReducer.cleanLabel(nil) == nil)
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 60, label: "  ", id: tea), now: t0)
        #expect(sut.state.timers.first?.label == "Timer")
    }

    // MARK: Stopwatch

    @Test("The stopwatch starts, pauses, resumes and resets")
    func stopwatchCycle() {
        var sut = TimersReducer()
        #expect(visible(sut.reduce(.stopwatchStart, now: t0)).first == .postStopwatch(Stopwatch(startedAt: t0, accumulated: 0)))
        #expect(visible(sut.reduce(.stopwatchPause, now: t0 + 10)).first == .postStopwatch(Stopwatch(startedAt: nil, accumulated: 10)))
        _ = sut.reduce(.stopwatchStart, now: t0 + 20)
        #expect(sut.state.stopwatch?.elapsed(at: t0 + 25) == 15)
        #expect(visible(sut.reduce(.stopwatchReset, now: t0 + 30)).first == .endStopwatch)
        #expect(sut.state.stopwatch == nil)
    }

    // MARK: Ranking and progress

    @Test("On the island: a done timer first, then the soonest running, then paused, then the stopwatch")
    func relevanceSoonestFirst() {
        var sut = TimersReducer()
        _ = sut.reduce(.start(duration: 600, label: nil, id: tea), now: t0)
        _ = sut.reduce(.start(duration: 300, label: nil, id: pasta), now: t0)
        let other = UUID()
        _ = sut.reduce(.start(duration: 900, label: nil, id: other), now: t0)
        _ = sut.reduce(.pause(other), now: t0)
        let state = sut.state
        #expect(state.relevance(of: pasta) > state.relevance(of: tea))
        #expect(state.relevance(of: tea) > state.relevance(of: other))
        #expect(state.relevance(of: other) > TimersState.stopwatchRelevance)
        _ = sut.reduce(.deadline, now: t0 + 300)
        #expect(sut.state.relevance(of: pasta) > sut.state.relevance(of: tea))
    }

    @Test("The ring's fraction left goes from 1 to 0")
    func fractionLeft() {
        let item = running(tea, duration: 600, endsAt: t0 + 600)
        #expect(item.fractionLeft(at: t0) == 1)
        #expect(item.fractionLeft(at: t0 + 300) == 0.5)
        #expect(item.fractionLeft(at: t0 + 700) == 0)
    }

    // MARK: URL scheme

    @Test("A label piled with combining marks stays short in every sense")
    func labelScalarsAreCapped() {
        let zalgo = String(repeating: "a" + String(repeating: "\u{0301}", count: 200), count: 40)
        let cleaned = TimersReducer.cleanLabel(zalgo)
        #expect((cleaned?.unicodeScalars.count ?? 0) <= TimersReducer.labelScalarLimit)
    }

    @Test("Odd timer URLs are refused")
    func oddTimerURLs() {
        func parse(_ string: String) -> TimerRequest? { URL(string: string).flatMap(TimerURL.parse) }
        #expect(parse("notched://timer?hours=1e308") == nil)
        #expect(parse("notched://timer?minutes=nan") == nil)
        #expect(parse("notched://timer?minutes=") == nil)
        #expect(parse("notched://timer?minutes=-1") == nil)
        #expect(parse("notched://timer?label=Tea") == nil)
    }

    @Test("A finished timer keeps ringing long enough for an alert that has to wait")
    func ringingOutlastsAWaitingAlert() {
        var sut = TimersReducer(doneHold: TimersReducer.ringing)
        let id = UUID()
        _ = sut.reduce(.start(duration: 60, label: nil, id: id), now: t0)
        _ = sut.reduce(.deadline, now: t0 + 60)
        // Still on the island 30 s later, e.g. while the user had it open.
        #expect(sut.reduce(.deadline, now: t0 + 90).allSatisfy { if case .end = $0 { false } else { true } })
        #expect(sut.reduce(.deadline, now: t0 + 60 + TimersReducer.ringing).contains(.end(id, toRecent: true)))
    }

    @Test("notched://timer URLs start timers")
    func urlParsing() {
        func parse(_ string: String) -> TimerRequest? { TimerURL.parse(URL(string: string)!) }
        #expect(parse("notched://timer?minutes=10&label=Tea") == TimerRequest(duration: 600, label: "Tea"))
        #expect(parse("notched://timer?seconds=90") == TimerRequest(duration: 90, label: nil))
        #expect(parse("notched://timer?hours=1&minutes=30") == TimerRequest(duration: 5400, label: nil))
        #expect(parse("notched://timer?minutes=2.5&label=Green%20tea") == TimerRequest(duration: 150, label: "Green tea"))
        #expect(parse("NOTCHED://TIMER?minutes=1") == TimerRequest(duration: 60, label: nil))
        #expect(parse("notched://timer") == nil)
        #expect(parse("notched://timer?minutes=0") == nil)
        #expect(parse("notched://timer?minutes=2000") == nil)
        #expect(parse("notched://timer?minutes=-5") == nil)
        #expect(parse("notched://timer?minutes=abc") == nil)
        #expect(parse("notched://debug?minutes=1") == nil)
        #expect(parse("https://timer?minutes=1") == nil)
    }
}
