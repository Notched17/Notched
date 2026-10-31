// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Calendar's countdown, alert and agenda rules (#48, #49).
@Suite("CalendarReducer")
struct CalendarReducerTests {
    /// 10:00 UTC on a fixed day, in a fixed time zone so the day boundaries are the same everywhere.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let t0 = Date(timeIntervalSince1970: 1_800_007_200)   // 10:00 UTC on a day boundary + 10 h
    let blue = ColorValue(red: 0, green: 0, blue: 255)

    private func config(_ edit: (inout CalendarConfig) -> Void = { _ in }) -> CalendarConfig {
        var config = CalendarConfig()
        config.calendar = Self.calendar
        edit(&config)
        return config
    }

    private func event(_ id: String, title: String = "Stand-up", at start: Date, minutes: Int = 30, allDay: Bool = false,
                       cancelled: Bool = false, declined: Bool = false, calendarID: String = "work", location: String? = nil,
                       notes: String? = nil) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: id, title: title, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay,
                              isCancelled: cancelled, isDeclined: declined, calendarID: calendarID, calendarName: "Work", color: blue,
                              location: location, urlString: nil, notes: notes)
    }

    private func ready(_ events: [CalendarEventSnapshot], now: Date? = nil, edit: (inout CalendarConfig) -> Void = { _ in }) -> CalendarReducer {
        var sut = CalendarReducer()
        let now = now ?? t0
        _ = sut.reduce(.configure(config(edit)), now: now)
        _ = sut.reduce(.access(true), now: now)
        _ = sut.reduce(.events(events), now: now)
        return sut
    }

    private func posts(_ effects: [CalendarReducer.Effect]) -> [CountdownInfo] {
        effects.compactMap { if case .post(let info, _) = $0 { info } else { nil } }
    }

    // MARK: Countdown

    @Test("Nothing shows more than 15 minutes ahead, then the countdown appears with whole minutes rounded up")
    func windowAndRounding() {
        var sut = ready([event("a", at: t0 + 30 * 60)])
        #expect(sut.state.countdown == nil)
        let at16 = sut.reduce(.tick, now: t0 + 14 * 60)            // 16 min left
        #expect(posts(at16).isEmpty)
        let at15 = sut.reduce(.tick, now: t0 + 15 * 60)            // exactly 15 left
        #expect(posts(at15).first?.minutesLeft == 15)
        let later = sut.reduce(.tick, now: t0 + 15 * 60 + 61)      // 13m59s left → 14
        #expect(posts(later).first?.minutesLeft == 14)
        let last = sut.reduce(.tick, now: t0 + 29 * 60 + 30)       // 30s left → 1
        #expect(posts(last).first?.minutesLeft == 1)
    }

    @Test("It reads Now from the start for five minutes, then ends")
    func nowThenEnds() {
        var sut = ready([event("a", at: t0 + 60)], now: t0)
        #expect(posts(sut.reduce(.tick, now: t0 + 60)).first?.hasStarted == true)
        #expect(sut.state.countdown?.hasStarted == true)
        _ = sut.reduce(.tick, now: t0 + 60 + 299)
        #expect(sut.state.countdown != nil)
        #expect(sut.reduce(.tick, now: t0 + 60 + 300).contains(.endCountdown))
        #expect(sut.state.countdown == nil)
    }

    @Test("A configurable window")
    func windowSetting() {
        let sut = ready([event("a", at: t0 + 20 * 60)], edit: { $0.countdownMinutes = 30 })
        #expect(sut.state.countdown?.minutesLeft == 20)
        let short = ready([event("a", at: t0 + 8 * 60)], edit: { $0.countdownMinutes = 5 })
        #expect(short.state.countdown == nil)
    }

    @Test("Declined, cancelled and left-out events never count down; all-day events don't either")
    func ineligible() {
        let soon = t0 + 5 * 60
        #expect(ready([event("a", at: soon, declined: true)]).state.countdown == nil)
        #expect(ready([event("a", at: soon, cancelled: true)]).state.countdown == nil)
        #expect(ready([event("a", at: soon, allDay: true)]).state.countdown == nil)
        #expect(ready([event("a", at: soon, calendarID: "holidays")], edit: { $0.excludedCalendars = ["holidays"] }).state.countdown == nil)
        #expect(ready([event("a", at: soon)]).state.countdown != nil)
    }

    @Test("An event that is coming beats one that just started")
    func comingBeatsStarted() {
        let sut = ready([event("started", at: t0 - 120), event("coming", at: t0 + 120)])
        #expect(sut.state.countdown?.eventID == "coming")
    }

    @Test("Of two coming events the earlier is shown, and an overlapping long one doesn't hide the next")
    func earliestWins() {
        let sut = ready([event("late", at: t0 + 600), event("early", at: t0 + 300)])
        #expect(sut.state.countdown?.eventID == "early")
    }

    @Test("An event already finished doesn't count down")
    func finished() {
        let sut = ready([event("old", at: t0 - 3600, minutes: 30)])
        #expect(sut.state.countdown == nil)
    }

    @Test("Without access nothing is shown, and losing access clears it")
    func accessGate() {
        var sut = ready([event("a", at: t0 + 300)])
        #expect(sut.state.countdown != nil)
        let effects = sut.reduce(.access(false), now: t0)
        #expect(effects.contains(.endCountdown))
        #expect(sut.state.agenda.isEmpty)
        #expect(sut.state.scheduledWake == nil)
    }

    // MARK: Alert

    @Test("It alerts once, a minute before, and not again")
    func alertsOnce() {
        var sut = ready([event("a", at: t0 + 600)])
        let before = sut.reduce(.tick, now: t0 + 600 - 61)
        #expect(!before.contains { if case .post(_, let alert) = $0 { alert } else { false } })
        let alert = sut.reduce(.tick, now: t0 + 600 - 60)
        #expect(alert.contains { if case .post(_, let alert) = $0 { alert } else { false } })
        let again = sut.reduce(.tick, now: t0 + 600 - 30)
        #expect(!again.contains { if case .post(_, let alert) = $0 { alert } else { false } })
        let atStart = sut.reduce(.tick, now: t0 + 600)
        #expect(!atStart.contains { if case .post(_, let alert) = $0 { alert } else { false } })
    }

    @Test("First seen inside the last minute still alerts once; first seen after the start never does")
    func lateDiscovery() {
        var inside = ready([], now: t0)
        let effects = inside.reduce(.events([event("a", at: t0 + 40)]), now: t0)
        #expect(effects.contains { if case .post(_, let alert) = $0 { alert } else { false } })
        let after = ready([event("b", at: t0 - 10)])
        #expect(after.state.alerted.isEmpty)
    }

    @Test("The alert can be turned off")
    func alertSetting() {
        var sut = ready([event("a", at: t0 + 600)], edit: { $0.alertBeforeStart = false })
        let effects = sut.reduce(.tick, now: t0 + 560)
        #expect(!effects.contains { if case .post(_, let alert) = $0 { alert } else { false } })
    }

    @Test("An event moved out of the window ends the countdown, and moving it back doesn't alert twice")
    func moved() {
        var sut = ready([event("a", at: t0 + 600)])
        _ = sut.reduce(.tick, now: t0 + 545)                      // alerts
        // Pushed half an hour out: beyond the 15-minute window, so the countdown goes.
        let moved = sut.reduce(.events([event("a", at: t0 + 1800)]), now: t0 + 545)
        #expect(moved.contains(.endCountdown))
        // Back inside the last minute: the same occurrence was already alerted.
        let back = sut.reduce(.events([event("a", at: t0 + 700)]), now: t0 + 645)
        #expect(posts(back).count == 1)
        #expect(!back.contains { if case .post(_, let alert) = $0 { alert } else { false } })
    }

    @Test("Deleting the event ends the countdown")
    func deleted() {
        var sut = ready([event("a", at: t0 + 300)])
        #expect(sut.reduce(.events([]), now: t0).contains(.endCountdown))
    }

    // MARK: Join

    @Test("The countdown carries the meeting link")
    func joinInCountdown() {
        let sut = ready([event("a", at: t0 + 300, location: "https://meet.google.com/abc-defg-hij")])
        #expect(sut.state.countdown?.join?.service == .meet)
        #expect(ready([event("a", at: t0 + 300, location: "Room 4")]).state.countdown?.join == nil)
    }

    // MARK: Agenda

    @Test("Today's remaining events then tomorrow's, all-day first, finished ones left out")
    func agenda() {
        let tomorrow = t0 + 24 * 3600
        let sut = ready([
            event("done", at: t0 - 3 * 3600),
            event("running", at: t0 - 600, minutes: 60),
            event("later", at: t0 + 4 * 3600),
            event("holiday", at: Self.calendar.startOfDay(for: t0), minutes: 24 * 60, allDay: true),
            event("tomorrow-am", at: tomorrow - 3600),
            event("tomorrow-allday", at: Self.calendar.startOfDay(for: tomorrow), minutes: 24 * 60, allDay: true),
            event("next-week", at: t0 + 5 * 24 * 3600),
        ])
        #expect(sut.state.agenda.map(\.id) == ["holiday#0", "running#0", "later#0", "tomorrow-allday#1", "tomorrow-am#1"])
        #expect(sut.state.agenda.first { $0.id == "running#0" }?.isInProgress == true)
        #expect(sut.state.agenda.first { $0.id == "later#0" }?.isInProgress == false)
        #expect(sut.state.agenda.filter(\.isTomorrow).count == 2)
    }

    @Test("An all-day event ending at midnight isn't also listed tomorrow")
    func allDayEdge() {
        let start = Self.calendar.startOfDay(for: t0)
        let sut = ready([event("d", at: start, minutes: 24 * 60, allDay: true)])
        #expect(sut.state.agenda.map(\.id) == ["d#0"])
    }

    @Test("An event spanning midnight is listed on both days")
    func spansMidnight() {
        let late = Self.calendar.startOfDay(for: t0) + 23 * 3600
        let sut = ready([event("late", at: late, minutes: 120)])
        #expect(sut.state.agenda.map(\.id) == ["late#0", "late#1"])
    }

    @Test("The agenda changes as time passes, and reports a change only when it did")
    func agendaUpdates() {
        var sut = ready([event("a", at: t0 + 600, minutes: 30)])
        #expect(!sut.reduce(.tick, now: t0 + 1).contains { if case .agendaChanged = $0 { true } else { false } })
        let after = sut.reduce(.tick, now: t0 + 600 + 31 * 60)
        #expect(after.contains(.agendaChanged([])))
    }

    // MARK: Wake

    @Test("It asks to wake for the window opening, the minute edge, the start, and the end of Now")
    func wakes() {
        var sut = ready([event("a", at: t0 + 3600)])
        #expect(sut.state.scheduledWake == t0 + 3600 - 15 * 60)
        _ = sut.reduce(.tick, now: t0 + 3600 - 15 * 60)             // countdown at 15
        #expect(sut.state.scheduledWake == t0 + 3600 - 14 * 60)      // next minute edge
        _ = sut.reduce(.tick, now: t0 + 3600 - 120)
        #expect(sut.state.scheduledWake == t0 + 3600 - 60)           // 1 minute left
        _ = sut.reduce(.tick, now: t0 + 3600 - 60)
        #expect(sut.state.scheduledWake == t0 + 3600)
        _ = sut.reduce(.tick, now: t0 + 3600)
        #expect(sut.state.scheduledWake == t0 + 3600 + 300)
    }

    @Test("With nothing coming it still wakes at midnight to roll the agenda")
    func midnightWake() {
        let sut = ready([])
        #expect(sut.state.scheduledWake == Self.calendar.startOfDay(for: t0) + 24 * 3600)
    }

    @Test("A wake effect is only sent when the time changed")
    func wakeNotRepeated() {
        var sut = ready([event("a", at: t0 + 3600)])
        let again = sut.reduce(.tick, now: t0 + 5)
        #expect(!again.contains { if case .wake = $0 { true } else { false } })
    }

    @Test("Random events never crash and keep the countdown consistent")
    func fuzz() {
        var generator = SystemRandomNumberGenerator()
        var sut = ready([])
        var now = t0
        for _ in 0..<600 {
            now += TimeInterval.random(in: 0...400, using: &generator)
            switch Int.random(in: 0..<5, using: &generator) {
            case 0:
                let events = (0..<Int.random(in: 0...5, using: &generator)).map { index in
                    event("e\(index)", at: now + TimeInterval.random(in: -3600...7200, using: &generator),
                          minutes: Int.random(in: 5...120, using: &generator), allDay: Int.random(in: 0..<6, using: &generator) == 0,
                          cancelled: Int.random(in: 0..<8, using: &generator) == 0, declined: Int.random(in: 0..<8, using: &generator) == 0)
                }
                _ = sut.reduce(.events(events), now: now)
            case 1: _ = sut.reduce(.access(Bool.random(using: &generator)), now: now)
            default: _ = sut.reduce(.tick, now: now)
            }
            if let countdown = sut.state.countdown {
                #expect(sut.state.hasAccess)
                #expect(countdown.minutesLeft >= 0 && countdown.minutesLeft <= 15)
                #expect(!(sut.state.events.first { $0.id == countdown.eventID }.map { $0.isAllDay || $0.isCancelled || $0.isDeclined } ?? true))
            }
            if let wake = sut.state.scheduledWake { #expect(wake > now) }
        }
    }
}
