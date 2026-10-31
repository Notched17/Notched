// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import Testing
@testable import Notched

/// A calendar the tests control, with no EventKit and no permission prompt.
@MainActor
final class FakeCalendarSource: CalendarEventSource {
    var authorization: CalendarAuthorization = .granted
    var allowsAccess = true
    var stored: [CalendarEventSnapshot] = []
    var onChange: (() -> Void)?
    private(set) var observing = false
    private(set) var accessRequests = 0

    func requestAccess() async -> Bool {
        accessRequests += 1
        authorization = allowsAccess ? .granted : .denied
        return allowsAccess
    }

    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        guard authorization == .granted else { return [] }
        return stored.filter { $0.start < end && $0.end > start }
    }

    func calendars() -> [CalendarInfo] { [CalendarInfo(id: "work", name: "Work", color: ColorValue(red: 0, green: 0, blue: 255))] }
    func startObserving() { observing = true }
    func stopObserving() { observing = false }

    /// The database changed.
    func change(_ events: [CalendarEventSnapshot]) {
        stored = events
        onChange?()
    }
}

/// The Calendar shell and the shared Today tab (#48, #49).
@MainActor
@Suite("CalendarModule")
struct CalendarModuleTests {
    private struct Rig {
        let module: CalendarModule
        let source: FakeCalendarSource
        let coordinator: ActivityCoordinator
        let today: TodayHub
    }

    private func makeRig(source: FakeCalendarSource = FakeCalendarSource()) -> Rig {
        let coordinator = ActivityCoordinator()
        let today = TodayHub()
        today.publishTabs = { [coordinator] tabs in coordinator.setTabs(tabs, from: TodayHub.pseudoModuleID) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "CalendarModuleTests.\(UUID().uuidString)")!)
        let context = ModuleContext(activities: ActivitySink(moduleID: CalendarModule.descriptor.id, coordinator: coordinator),
                                    scheduler: RefreshScheduler(), settings: settings, services: ModuleServices(today: today), previousSessionCrashed: false)
        return Rig(module: CalendarModule(context: context, source: source), source: source, coordinator: coordinator, today: today)
    }

    private func event(_ id: String, minutesFromNow: Int, location: String? = nil) -> CalendarEventSnapshot {
        let start = Date().addingTimeInterval(TimeInterval(minutesFromNow * 60))
        return CalendarEventSnapshot(id: id, title: "Stand-up", start: start, end: start.addingTimeInterval(1800), isAllDay: false, isCancelled: false,
                                     isDeclined: false, calendarID: "work", calendarName: "Work", color: ColorValue(red: 0, green: 0, blue: 255),
                                     location: location, urlString: nil, notes: nil)
    }

    @Test("Starting adds the Today section and the tab; stopping removes both and watchers")
    func startStop() {
        let rig = makeRig()
        rig.module.start()
        #expect(rig.today.sections.map(\.id) == ["calendar"])
        #expect(rig.coordinator.moduleTabs.map(\.id) == ["today"])
        #expect(rig.source.observing)
        rig.module.stop()
        #expect(rig.today.sections.isEmpty)
        #expect(rig.coordinator.moduleTabs.isEmpty)
        #expect(!rig.source.observing)
        #expect(rig.coordinator.live.isEmpty)
    }

    @Test("An event soon shows a live countdown; a change in the calendar updates it; a delete ends it")
    func countdownFollowsCalendar() {
        let rig = makeRig()
        rig.source.stored = [event("a", minutesFromNow: 10, location: "https://zoom.us/j/9")]
        rig.module.start()
        #expect(rig.coordinator.live.map(\.id) == [CalendarModule.activityID])
        #expect(rig.module.model.agenda.count == 1)
        #expect(rig.module.model.agenda.first?.join?.service == .zoom)

        rig.source.change([event("a", minutesFromNow: 40)])
        #expect(rig.coordinator.live.isEmpty)
        #expect(rig.module.model.agenda.count == 1)

        rig.source.change([event("b", minutesFromNow: 5)])
        #expect(rig.coordinator.live.count == 1)
        rig.source.change([])
        #expect(rig.coordinator.live.isEmpty)
        #expect(rig.module.model.agenda.isEmpty)
        rig.module.stop()
    }

    @Test("An event in its last minute expands the island once")
    func alertExpands() {
        let rig = makeRig()
        rig.source.stored = [event("a", minutesFromNow: 0)]
        rig.source.stored[0].start = Date().addingTimeInterval(40)
        rig.source.stored[0].end = Date().addingTimeInterval(1840)
        rig.module.start()
        #expect(rig.coordinator.alert != nil)
        rig.module.stop()
    }

    @Test("Denied access shows the state and no events; allowing it later fills the agenda")
    func denied() {
        let source = FakeCalendarSource()
        source.authorization = .denied
        source.stored = [event("a", minutesFromNow: 5)]
        let rig = makeRig(source: source)
        rig.module.start()
        #expect(rig.module.model.authorization == .denied)
        #expect(rig.module.model.agenda.isEmpty)
        #expect(rig.coordinator.live.isEmpty)
        #expect(rig.today.sections.count == 1)       // the section stays, to say why
        source.authorization = .granted
        source.onChange?()
        #expect(rig.module.model.authorization == .granted)
        #expect(rig.module.model.agenda.count == 1)
        rig.module.stop()
    }

    @Test("Turning it on asks macOS once when it hasn't been asked")
    func asksWhenUndetermined() async {
        let source = FakeCalendarSource()
        source.authorization = .notDetermined
        source.stored = [event("a", minutesFromNow: 5)]
        let rig = makeRig(source: source)
        rig.module.start()
        #expect(rig.module.model.authorization == .notDetermined)
        for _ in 0..<50 where source.accessRequests == 0 { await Task.yield() }
        for _ in 0..<50 where rig.module.model.authorization != .granted { await Task.yield() }
        #expect(source.accessRequests == 1)
        #expect(rig.module.model.authorization == .granted)
        #expect(rig.module.model.agenda.count == 1)
        rig.module.stop()
    }

    @Test("A calendar change after stopping does nothing")
    func stoppedIgnores() {
        let rig = makeRig()
        rig.module.start()
        rig.module.stop()
        rig.source.change([event("a", minutesFromNow: 5)])
        #expect(rig.coordinator.live.isEmpty)
        #expect(rig.module.model.agenda.isEmpty)
    }

    @Test("Switching it on and off five times leaves nothing behind")
    func neverLeaks() {
        let rig = makeRig()
        rig.source.stored = [event("a", minutesFromNow: 5)]
        for _ in 0..<5 {
            rig.module.start()
            #expect(rig.coordinator.live.count == 1)
            rig.module.stop()
            #expect(rig.coordinator.live.isEmpty)
            #expect(rig.coordinator.moduleTabs.isEmpty)
            #expect(rig.today.sections.isEmpty)
            #expect(!rig.source.observing)
        }
    }
}

/// The Today tab's shared host.
@MainActor
@Suite("TodayHub")
struct TodayHubTests {
    private func section(_ id: String, module: ModuleID, slot: TodaySlot) -> TodaySection {
        TodaySection(id: id, moduleID: module, slot: slot, content: IslandRegion { Text(id) })
    }

    @Test("The layout follows which slots are present")
    func layouts() {
        #expect(TodayLayout.make(slots: []) == TodayLayout(hasHeader: false, columns: [], rowLimit: 3))
        #expect(TodayLayout.make(slots: [.leading]) == TodayLayout(hasHeader: false, columns: [.leading], rowLimit: 3))
        #expect(TodayLayout.make(slots: [.trailing, .leading]) == TodayLayout(hasHeader: false, columns: [.leading, .trailing], rowLimit: 3))
        #expect(TodayLayout.make(slots: [.header, .leading, .trailing]) == TodayLayout(hasHeader: true, columns: [.leading, .trailing], rowLimit: 2))
        #expect(TodayLayout.make(slots: [.header]) == TodayLayout(hasHeader: true, columns: [], rowLimit: 3))
    }

    @Test("The tab exists while any section does, and goes with the last one")
    func tabLifetime() {
        let hub = TodayHub()
        var published: [[String]] = []
        hub.publishTabs = { published.append($0.map(\.id)) }
        hub.set(section("calendar", module: "calendar", slot: .leading))
        hub.set(section("reminders", module: "reminders", slot: .trailing))
        hub.remove(moduleID: "calendar")
        #expect(hub.sections.map(\.id) == ["reminders"])
        hub.remove(moduleID: "reminders")
        #expect(published == [["today"], ["today"], ["today"], []])
        hub.remove(moduleID: "reminders")
        #expect(published.count == 4)    // nothing to remove, nothing published
    }

    @Test("Setting a section again replaces it")
    func replaces() {
        let hub = TodayHub()
        hub.set(section("calendar", module: "calendar", slot: .leading))
        hub.set(section("calendar", module: "calendar", slot: .trailing))
        #expect(hub.sections.count == 1)
        #expect(hub.sections(in: .trailing).count == 1)
        #expect(hub.sections(in: .leading).isEmpty)
    }

    @Test("Calendar's settings default sensibly and ignore bad values")
    func settings() {
        let defaults = UserDefaults(suiteName: "CalendarSettingsTests.\(UUID().uuidString)")!
        let settings = CalendarSettings(defaults: defaults)
        #expect(settings.countdownMinutes == 15)
        #expect(settings.alertBeforeStart)
        #expect(settings.excludedCalendars.isEmpty)
        defaults.set(7, forKey: CalendarSettings.Key.countdownMinutes)
        #expect(CalendarSettings(defaults: defaults).countdownMinutes == 15)
        settings.countdownMinutes = 30
        settings.excludedCalendars = ["x"]
        #expect(CalendarSettings(defaults: defaults).reducerConfig.countdownMinutes == 30)
        #expect(CalendarSettings(defaults: defaults).reducerConfig.excludedCalendars == ["x"])
    }
}
