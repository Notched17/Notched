// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Reminders' list, undo window and banner rules (#50).
@Suite("RemindersReducer")
struct RemindersReducerTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 10:00 UTC on a day boundary + 10 h.
    let t0 = Date(timeIntervalSince1970: 1_800_007_200)
    let orange = ColorValue(red: 255, green: 149, blue: 0)

    private func reminder(_ id: String, title: String? = nil, due: Date?, hasTime: Bool = true, list: String = "home", priority: Int = 0) -> ReminderSnapshot {
        ReminderSnapshot(id: id, title: title ?? id, due: due, hasTime: hasTime, listID: list, listName: "Home", color: orange, priority: priority)
    }

    private func ready(_ reminders: [ReminderSnapshot], edit: (inout RemindersConfig) -> Void = { _ in }) -> RemindersReducer {
        var config = RemindersConfig()
        config.calendar = Self.calendar
        edit(&config)
        var sut = RemindersReducer()
        _ = sut.reduce(.configure(config), now: t0)
        _ = sut.reduce(.access(true), now: t0)
        _ = sut.reduce(.reminders(reminders), now: t0)
        return sut
    }

    private func ids(_ sut: RemindersReducer) -> [String] { sut.state.items.map(\.id) }

    private func commits(_ effects: [RemindersReducer.Effect]) -> [String] {
        effects.compactMap { if case .commit(let id) = $0 { id } else { nil } }
    }

    private func banners(_ effects: [RemindersReducer.Effect]) -> [ReminderDueSoon] {
        effects.compactMap { if case .dueSoon(let banner) = $0 { banner } else { nil } }
    }

    // MARK: List

    @Test("Overdue first, then today; each by time, timed before date-only")
    func ordering() {
        let startOfDay = Self.calendar.startOfDay(for: t0)
        let sut = ready([
            reminder("later", due: t0 + 3 * 3600),
            reminder("dateOnly", due: startOfDay, hasTime: false),
            reminder("earlier", due: t0 + 3600),
            reminder("overdueTimed", due: t0 - 3600),
            reminder("overdueYesterday", due: startOfDay - 3600 * 5, hasTime: false),
        ])
        #expect(ids(sut) == ["overdueTimed", "overdueYesterday", "earlier", "later", "dateOnly"])
        #expect(sut.state.items.first { $0.id == "overdueTimed" }?.isOverdue == true)
        #expect(sut.state.items.first { $0.id == "dateOnly" }?.isOverdue == false)
        #expect(sut.state.items.first { $0.id == "overdueYesterday" }?.isOverdue == true)
    }

    @Test("Priority breaks a tie between equal due times")
    func priorityTie() {
        let sut = ready([reminder("none", due: t0 + 600, priority: 0), reminder("high", due: t0 + 600, priority: 1), reminder("low", due: t0 + 600, priority: 9)])
        #expect(ids(sut) == ["high", "low", "none"])
    }

    @Test("Reminders with no date or due after today aren't listed")
    func notToday() {
        let sut = ready([reminder("none", due: nil), reminder("tomorrow", due: t0 + 24 * 3600), reminder("today", due: t0 + 3600)])
        #expect(ids(sut) == ["today"])
    }

    @Test("Left-out lists are hidden")
    func excludedLists() {
        let sut = ready([reminder("a", due: t0 + 60, list: "work"), reminder("b", due: t0 + 60, list: "home")], edit: { $0.excludedLists = ["work"] })
        #expect(ids(sut) == ["b"])
    }

    @Test("Without access nothing is listed, and losing access clears it")
    func accessGate() {
        var sut = ready([reminder("a", due: t0 + 60)])
        #expect(ids(sut) == ["a"])
        let effects = sut.reduce(.access(false), now: t0)
        #expect(effects.contains(.itemsChanged([])))
        #expect(sut.state.scheduledWake == nil)
    }

    @Test("The list is reported only when it changed")
    func changeOnly() {
        var sut = ready([reminder("a", due: t0 + 3600)])
        let same = sut.reduce(.reminders([reminder("a", due: t0 + 3600)]), now: t0)
        #expect(!same.contains { if case .itemsChanged = $0 { true } else { false } })
    }

    @Test("A timed reminder turns overdue when its time passes")
    func becomesOverdue() {
        var sut = ready([reminder("a", due: t0 + 600)])
        #expect(sut.state.items[0].isOverdue == false)
        #expect(sut.state.scheduledWake == t0 + 600)
        let effects = sut.reduce(.tick, now: t0 + 601)
        #expect(sut.state.items[0].isOverdue)
        #expect(effects.contains { if case .itemsChanged = $0 { true } else { false } })
    }

    @Test("At midnight today's date-only reminders become overdue and tomorrow's come in")
    func midnight() {
        let startOfDay = Self.calendar.startOfDay(for: t0)
        var sut = ready([reminder("dateOnly", due: startOfDay, hasTime: false), reminder("tomorrow", due: startOfDay + 24 * 3600 + 3600)])
        #expect(ids(sut) == ["dateOnly"])
        #expect(sut.state.scheduledWake == startOfDay + 24 * 3600)
        _ = sut.reduce(.tick, now: startOfDay + 24 * 3600 + 5)
        #expect(ids(sut) == ["dateOnly", "tomorrow"])
        #expect(sut.state.items.first { $0.id == "dateOnly" }?.isOverdue == true)
    }

    // MARK: Undo window

    @Test("Ticking shows it done at once but saves nothing for 8 seconds")
    func tickIsDeferred() {
        var sut = ready([reminder("a", due: t0 + 600)])
        let effects = sut.reduce(.complete("a"), now: t0)
        #expect(commits(effects).isEmpty)
        #expect(sut.state.items[0].isPendingComplete)
        #expect(sut.state.scheduledWake == t0 + 8)
        #expect(commits(sut.reduce(.tick, now: t0 + 7.9)).isEmpty)
        let saved = sut.reduce(.tick, now: t0 + 8)
        #expect(commits(saved) == ["a"])
        #expect(ids(sut).isEmpty)     // hidden while the store catches up
    }

    @Test("Undo inside the window cancels the save for good")
    func undo() {
        var sut = ready([reminder("a", due: t0 + 600)])
        _ = sut.reduce(.complete("a"), now: t0)
        _ = sut.reduce(.undo("a"), now: t0 + 3)
        #expect(sut.state.items[0].isPendingComplete == false)
        #expect(commits(sut.reduce(.tick, now: t0 + 20)).isEmpty)
    }

    @Test("Ticking twice doesn't restart the window")
    func tickTwice() {
        var sut = ready([reminder("a", due: t0 + 600)])
        _ = sut.reduce(.complete("a"), now: t0)
        _ = sut.reduce(.complete("a"), now: t0 + 5)
        #expect(commits(sut.reduce(.tick, now: t0 + 8)) == ["a"])
    }

    @Test("A reminder being saved can't be ticked again")
    func noDoubleSave() {
        var sut = ready([reminder("a", due: t0 + 600)])
        _ = sut.reduce(.complete("a"), now: t0)
        _ = sut.reduce(.tick, now: t0 + 8)
        #expect(sut.reduce(.complete("a"), now: t0 + 9).isEmpty)
        #expect(sut.state.pending.isEmpty)
    }

    @Test("Ticking an unknown reminder does nothing")
    func tickUnknown() {
        var sut = ready([reminder("a", due: t0 + 600)])
        #expect(sut.reduce(.complete("zzz"), now: t0).isEmpty)
    }

    @Test("Several ticks save separately, each at its own time")
    func severalTicks() {
        var sut = ready([reminder("a", due: t0 + 600), reminder("b", due: t0 + 700)])
        _ = sut.reduce(.complete("a"), now: t0)
        _ = sut.reduce(.complete("b"), now: t0 + 4)
        #expect(commits(sut.reduce(.tick, now: t0 + 8)) == ["a"])
        #expect(commits(sut.reduce(.tick, now: t0 + 12)) == ["b"])
    }

    @Test("Quitting saves what is still pending, right away")
    func quit() {
        var sut = ready([reminder("a", due: t0 + 600), reminder("b", due: t0 + 700)])
        _ = sut.reduce(.complete("b"), now: t0)
        _ = sut.reduce(.complete("a"), now: t0)
        #expect(commits(sut.reduce(.quit, now: t0 + 1)) == ["a", "b"])
        #expect(commits(sut.reduce(.quit, now: t0 + 2)).isEmpty)
    }

    @Test("A reminder that vanishes while pending is dropped without a save")
    func vanishes() {
        var sut = ready([reminder("a", due: t0 + 600), reminder("b", due: t0 + 700)])
        _ = sut.reduce(.complete("a"), now: t0)
        _ = sut.reduce(.reminders([reminder("b", due: t0 + 700)]), now: t0 + 2)
        #expect(commits(sut.reduce(.tick, now: t0 + 20)).isEmpty)
        #expect(sut.state.pending.isEmpty)
    }

    @Test("A store refresh during the window keeps the tick pending")
    func refreshKeepsPending() {
        var sut = ready([reminder("a", due: t0 + 600)])
        _ = sut.reduce(.complete("a"), now: t0)
        _ = sut.reduce(.reminders([reminder("a", due: t0 + 600)]), now: t0 + 3)
        #expect(sut.state.items[0].isPendingComplete)
        #expect(commits(sut.reduce(.tick, now: t0 + 8)) == ["a"])
    }

    @Test("A failed save shows the reminder again; a refresh also brings back one still open")
    func failedSave() {
        var sut = ready([reminder("a", due: t0 + 600)])
        _ = sut.reduce(.complete("a"), now: t0)
        _ = sut.reduce(.tick, now: t0 + 8)
        #expect(ids(sut).isEmpty)
        _ = sut.reduce(.commitFailed("a"), now: t0 + 8)
        #expect(ids(sut) == ["a"])
        _ = sut.reduce(.complete("a"), now: t0 + 9)
        _ = sut.reduce(.tick, now: t0 + 17)
        _ = sut.reduce(.reminders([reminder("a", due: t0 + 600)]), now: t0 + 18)
        #expect(ids(sut) == ["a"])
    }

    // MARK: Banner

    @Test("The due-soon banner is off unless asked for")
    func bannerOff() {
        var sut = ready([reminder("a", due: t0 + 600)])
        #expect(banners(sut.reduce(.tick, now: t0 + 100)).isEmpty)
    }

    @Test("It fires once, 15 minutes before, never for date-only or overdue reminders")
    func bannerRules() {
        let startOfDay = Self.calendar.startOfDay(for: t0)
        var sut = ready([reminder("soon", due: t0 + 20 * 60), reminder("dateOnly", due: startOfDay, hasTime: false), reminder("late", due: t0 - 60)],
                        edit: { $0.dueSoonBanner = true })
        #expect(sut.state.scheduledWake == t0 + 5 * 60)       // 15 min before "soon"
        #expect(banners(sut.reduce(.tick, now: t0 + 4 * 60)).isEmpty)
        let fired = banners(sut.reduce(.tick, now: t0 + 5 * 60))
        #expect(fired == [ReminderDueSoon(id: "soon", title: "soon", due: t0 + 20 * 60)])
        #expect(banners(sut.reduce(.tick, now: t0 + 6 * 60)).isEmpty)
        #expect(banners(sut.reduce(.reminders(sut.state.reminders), now: t0 + 7 * 60)).isEmpty)
    }

    @Test("A ticked reminder gets no banner")
    func bannerSkipsTicked() {
        var sut = ready([reminder("soon", due: t0 + 20 * 60)], edit: { $0.dueSoonBanner = true })
        _ = sut.reduce(.complete("soon"), now: t0 + 5 * 60 - 1)
        #expect(banners(sut.reduce(.tick, now: t0 + 5 * 60)).isEmpty)
    }

    @Test("A burst of reminders gives at most three banners")
    func bannerCap() {
        let many = (0..<6).map { reminder("r\($0)", due: t0 + 10 * 60 + Double($0)) }
        var sut = ready([], edit: { $0.dueSoonBanner = true })
        #expect(banners(sut.reduce(.reminders(many), now: t0)).count == 3)
        #expect(banners(sut.reduce(.tick, now: t0 + 1)).isEmpty)
    }

    @Test("Random events never crash and keep the invariants")
    func fuzz() {
        var generator = SystemRandomNumberGenerator()
        var sut = ready([], edit: { $0.dueSoonBanner = true })
        var now = t0
        for _ in 0..<600 {
            now += TimeInterval.random(in: 0...20, using: &generator)
            switch Int.random(in: 0..<7, using: &generator) {
            case 0:
                let list = (0..<Int.random(in: 0...6, using: &generator)).map { index in
                    reminder("r\(index)", due: now + TimeInterval.random(in: -7200...36_000, using: &generator), hasTime: Bool.random(using: &generator))
                }
                _ = sut.reduce(.reminders(list), now: now)
            case 1: _ = sut.reduce(.complete("r\(Int.random(in: 0..<6, using: &generator))"), now: now)
            case 2: _ = sut.reduce(.undo("r\(Int.random(in: 0..<6, using: &generator))"), now: now)
            case 3: _ = sut.reduce(.access(Int.random(in: 0..<5, using: &generator) != 0), now: now)
            case 4: _ = sut.reduce(.commitFailed("r\(Int.random(in: 0..<6, using: &generator))"), now: now)
            default: _ = sut.reduce(.tick, now: now)
            }
            // A pending reminder is always one that exists, and nothing pending is saved twice.
            let present = Set(sut.state.reminders.map(\.id))
            #expect(sut.state.pending.keys.allSatisfy(present.contains))
            #expect(sut.state.pending.keys.allSatisfy { !sut.state.committing.contains($0) })
            if let wake = sut.state.scheduledWake { #expect(wake > now) }
            if !sut.state.hasAccess { #expect(sut.state.items.isEmpty) }
        }
    }
}
