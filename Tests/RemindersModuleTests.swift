// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Reminders the tests control, with no EventKit and no permission prompt.
@MainActor
final class FakeReminderSource: ReminderSource {
    var authorization: CalendarAuthorization = .granted
    var allowsAccess = true
    var stored: [ReminderSnapshot] = []
    var onChange: (() -> Void)?
    private(set) var observing = false
    private(set) var accessRequests = 0
    private(set) var completed: [String] = []
    var failsToSave = false

    func requestAccess() async -> Bool {
        accessRequests += 1
        authorization = allowsAccess ? .granted : .denied
        return allowsAccess
    }

    func incompleteReminders(dueBefore end: Date) async -> [ReminderSnapshot] {
        guard authorization == .granted else { return [] }
        return stored.filter { ($0.due ?? .distantFuture) < end }
    }

    func complete(id: String) throws {
        if failsToSave { throw ReminderStoreError.notFound }
        completed.append(id)
        stored.removeAll { $0.id == id }
    }

    func lists() -> [ReminderListInfo] { [ReminderListInfo(id: "home", name: "Home", color: ColorValue(red: 255, green: 149, blue: 0))] }
    func startObserving() { observing = true }
    func stopObserving() { observing = false }
}

/// The Reminders shell (#50).
@MainActor
@Suite("RemindersModule")
struct RemindersModuleTests {
    private struct Rig {
        let module: RemindersModule
        let source: FakeReminderSource
        let coordinator: ActivityCoordinator
        let today: TodayHub
    }

    private func makeRig(source: FakeReminderSource = FakeReminderSource()) -> Rig {
        let coordinator = ActivityCoordinator()
        let today = TodayHub()
        today.publishTabs = { [coordinator] tabs in coordinator.setTabs(tabs, from: TodayHub.pseudoModuleID) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "RemindersModuleTests.\(UUID().uuidString)")!)
        let context = ModuleContext(activities: ActivitySink(moduleID: RemindersModule.descriptor.id, coordinator: coordinator),
                                    scheduler: RefreshScheduler(), settings: settings, services: ModuleServices(today: today), previousSessionCrashed: false)
        return Rig(module: RemindersModule(context: context, source: source), source: source, coordinator: coordinator, today: today)
    }

    /// Overdue by default, so it is always on today's list whatever time the test runs.
    private func reminder(_ id: String, minutesFromNow: Int = -10) -> ReminderSnapshot {
        ReminderSnapshot(id: id, title: "Call Sam", due: Date().addingTimeInterval(TimeInterval(minutesFromNow * 60)), hasTime: true,
                         listID: "home", listName: "Home", color: ColorValue(red: 255, green: 149, blue: 0), priority: 0)
    }

    /// Lets the module's fetch task run.
    private func settle(_ rig: Rig, until done: () -> Bool) async {
        for _ in 0..<100 where !done() { await Task.yield() }
    }

    @Test("Starting adds the right-hand Today section; stopping removes it and everything it watches")
    func startStop() async {
        let rig = makeRig()
        rig.source.stored = [reminder("a")]
        rig.module.start()
        #expect(rig.today.sections.map(\.id) == ["reminders"])
        #expect(rig.today.sections.first?.slot == .trailing)
        #expect(rig.coordinator.moduleTabs.map(\.id) == ["today"])
        #expect(rig.source.observing)
        await settle(rig) { !rig.module.model.items.isEmpty }
        #expect(rig.module.model.items.map(\.id) == ["a"])
        rig.module.stop()
        #expect(rig.today.sections.isEmpty)
        #expect(rig.coordinator.moduleTabs.isEmpty)
        #expect(!rig.source.observing)
    }

    @Test("A tick is saved after the undo window, not before")
    func tickSavesLater() async {
        let rig = makeRig()
        rig.source.stored = [reminder("a")]
        rig.module.start()
        await settle(rig) { !rig.module.model.items.isEmpty }
        rig.module.model.actions.complete("a")
        #expect(rig.module.model.items.first?.isPendingComplete == true)
        #expect(rig.source.completed.isEmpty)
        rig.module.send(.tick)
        #expect(rig.source.completed.isEmpty)       // 8 s have not passed
        rig.module.stop()
    }

    @Test("Undo means it is never saved")
    func undoNeverSaves() async {
        let rig = makeRig()
        rig.source.stored = [reminder("a")]
        rig.module.start()
        await settle(rig) { !rig.module.model.items.isEmpty }
        rig.module.model.actions.complete("a")
        rig.module.model.actions.undo("a")
        #expect(rig.module.model.items.first?.isPendingComplete == false)
        rig.module.stop()
        #expect(rig.source.completed.isEmpty)
    }

    @Test("Stopping or quitting while a tick is pending saves it")
    func stopSavesPending() async {
        let rig = makeRig()
        rig.source.stored = [reminder("a"), reminder("b")]
        rig.module.start()
        await settle(rig) { rig.module.model.items.count == 2 }
        rig.module.model.actions.complete("a")
        rig.module.stop()
        #expect(rig.source.completed == ["a"])
    }

    @Test("A failed save brings the reminder back")
    func failedSave() async {
        let rig = makeRig()
        rig.source.stored = [reminder("a")]
        rig.source.failsToSave = true
        rig.module.start()
        await settle(rig) { !rig.module.model.items.isEmpty }
        rig.module.model.actions.complete("a")
        rig.module.send(.quit)
        #expect(rig.source.completed.isEmpty)
        #expect(rig.module.model.items.map(\.id) == ["a"])
        rig.module.stop()
    }

    @Test("A change in the store refreshes the list")
    func storeChange() async {
        let rig = makeRig()
        rig.module.start()
        await settle(rig) { rig.module.model.hasLoaded }
        #expect(rig.module.model.items.isEmpty)
        rig.source.stored = [reminder("new")]
        rig.source.onChange?()
        await settle(rig) { !rig.module.model.items.isEmpty }
        #expect(rig.module.model.items.map(\.id) == ["new"])
        rig.module.stop()
    }

    @Test("Denied access shows the state and no reminders")
    func denied() {
        let source = FakeReminderSource()
        source.authorization = .denied
        source.stored = [reminder("a")]
        let rig = makeRig(source: source)
        rig.module.start()
        #expect(rig.module.model.authorization == .denied)
        #expect(rig.module.model.items.isEmpty)
        #expect(rig.today.sections.count == 1)
        rig.module.stop()
    }

    @Test("Turning it on asks macOS once when it hasn't been asked")
    func asksWhenUndetermined() async {
        let source = FakeReminderSource()
        source.authorization = .notDetermined
        source.stored = [reminder("a")]
        let rig = makeRig(source: source)
        rig.module.start()
        await settle(rig) { rig.module.model.items.count == 1 }
        #expect(source.accessRequests == 1)
        #expect(rig.module.model.authorization == .granted)
        rig.module.stop()
    }

    @Test("A fetch that finishes after stopping is ignored")
    func lateFetch() async {
        let rig = makeRig()
        rig.source.stored = [reminder("a")]
        rig.module.start()
        rig.module.stop()
        await settle(rig) { false }
        #expect(rig.module.model.items.isEmpty)
    }

    @Test("Switching it on and off five times leaves nothing behind")
    func neverLeaks() async {
        let rig = makeRig()
        rig.source.stored = [reminder("a")]
        for _ in 0..<5 {
            rig.module.start()
            await settle(rig) { !rig.module.model.items.isEmpty }
            rig.module.stop()
            #expect(rig.today.sections.isEmpty)
            #expect(rig.coordinator.moduleTabs.isEmpty)
            #expect(!rig.source.observing)
        }
    }

    @Test("Reminders' settings default sensibly")
    func settings() {
        let defaults = UserDefaults(suiteName: "RemindersSettingsTests.\(UUID().uuidString)")!
        let settings = RemindersSettings(defaults: defaults)
        #expect(!settings.dueSoonBanner)
        #expect(settings.excludedLists.isEmpty)
        settings.dueSoonBanner = true
        settings.excludedLists = ["x"]
        let reloaded = RemindersSettings(defaults: defaults)
        #expect(reloaded.reducerConfig.dueSoonBanner)
        #expect(reloaded.reducerConfig.excludedLists == ["x"])
    }
}
