// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// A pasteboard the tests control. It counts how often contents were read, so
/// a test can prove a skipped copy was never read.
@MainActor
final class FakeClipboardPasteboard: ClipboardPasteboard {
    var changeCount = 1
    var typeIdentifiers: [String] = []
    var frontmostApp: (bundleID: String?, name: String?) = ("com.apple.Safari", "Safari")
    var contents: ClipboardCandidate?
    private(set) var reads = 0
    private(set) var written: [ClipboardEntry] = []
    var writeSucceeds = true

    /// Something was copied.
    func copy(_ text: String, kind: ClipboardKind = .text, types: [String] = ["public.utf8-plain-text"], app: String? = "com.apple.Safari") {
        changeCount += 1
        typeIdentifiers = types
        frontmostApp = (app, app)
        contents = ClipboardCandidate(kind: kind, text: text, contentHash: ClipboardHash.hash(kind: kind, text: text))
    }

    func readCandidate(store: ClipboardStore) -> ClipboardCandidate? {
        reads += 1
        return contents
    }

    func write(_ entry: ClipboardEntry, store: ClipboardStore) -> Bool {
        guard writeSucceeds else { return false }
        written.append(entry)
        changeCount += 1
        return true
    }
}

/// The clipboard shell: polling, saving, hotkey-free, with a fake pasteboard (#45).
@MainActor
@Suite("ClipboardModule")
struct ClipboardModuleTests {
    private struct Rig {
        let module: ClipboardModule
        let pasteboard: FakeClipboardPasteboard
        let coordinator: ActivityCoordinator
        let scheduler: RefreshScheduler
        let settings: SettingsStore
        let store: ClipboardStore
        let commands: IslandCommands
    }

    private func makeRig(directory: URL? = nil, settings: SettingsStore? = nil, pasteboard: FakeClipboardPasteboard = FakeClipboardPasteboard()) -> Rig {
        let coordinator = ActivityCoordinator()
        let scheduler = RefreshScheduler()
        let settings = settings ?? SettingsStore(defaults: UserDefaults(suiteName: "ClipboardModuleTests.\(UUID().uuidString)")!)
        let commands = IslandCommands()
        let context = ModuleContext(activities: ActivitySink(moduleID: ClipboardModule.descriptor.id, coordinator: coordinator), scheduler: scheduler,
                                    settings: settings, services: ModuleServices(islandCommands: commands), previousSessionCrashed: false)
        let store = ClipboardStore(directory: directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardModuleTests-\(UUID().uuidString)"))
        let module = ClipboardModule(context: context, pasteboard: pasteboard, store: store, usesHotkey: false)
        return Rig(module: module, pasteboard: pasteboard, coordinator: coordinator, scheduler: scheduler, settings: settings, store: store, commands: commands)
    }

    /// What the scheduler's poll does on each tick.
    private func poll(_ rig: Rig) { rig.module.send(.tick(changeCount: rig.pasteboard.changeCount)) }

    @Test("Starting registers one poll and the tab; stopping removes both")
    func startStop() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.module.start()
        #expect(rig.scheduler.registrationCount == 1)
        #expect(rig.coordinator.moduleTabs.map(\.id) == ["clipboard"])
        rig.module.stop()
        #expect(rig.scheduler.registrationCount == 0)
        #expect(rig.coordinator.moduleTabs.isEmpty)
    }

    @Test("What was on the clipboard at start is not recorded; later copies are")
    func firstLookIsSilent() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.pasteboard.copy("already there")
        rig.module.start()
        poll(rig)
        #expect(rig.module.model.entries.isEmpty)
        #expect(rig.pasteboard.reads == 0)
        rig.pasteboard.copy("new")
        poll(rig)
        #expect(rig.module.model.entries.map(\.text) == ["new"])
        rig.module.stop()
    }

    @Test("Polling an unchanged clipboard never reads it")
    func idlePollReadsNothing() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.module.start()
        for _ in 0..<100 { poll(rig) }
        #expect(rig.pasteboard.reads == 0)
        rig.module.stop()
    }

    @Test("A password manager's copy is never read, let alone kept")
    func privateCopyIsNotRead() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.module.start()
        rig.pasteboard.copy("hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        poll(rig)
        rig.pasteboard.copy("also secret", app: "com.agilebits.onepassword7")
        poll(rig)
        #expect(rig.pasteboard.reads == 0)
        #expect(rig.module.model.entries.isEmpty)
        rig.module.stop()
    }

    @Test("Clicking an entry puts it back, collapses the island, and isn't recorded again")
    func copyBack() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        var collapsed = 0
        rig.commands.collapse = { collapsed += 1 }
        rig.module.start()
        rig.pasteboard.copy("one")
        poll(rig)
        rig.pasteboard.copy("two")
        poll(rig)
        let first = rig.module.model.entries.last!
        rig.module.model.actions.copy(first.id)
        #expect(rig.pasteboard.written.map(\.text) == ["one"])
        #expect(collapsed == 1)
        poll(rig)
        #expect(rig.module.model.entries.map(\.text) == ["two", "one"])
        rig.module.stop()
    }

    @Test("A copy-back that fails leaves things as they were")
    func copyBackFails() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        var collapsed = 0
        rig.commands.collapse = { collapsed += 1 }
        rig.module.start()
        rig.pasteboard.copy("one")
        poll(rig)
        rig.pasteboard.writeSucceeds = false
        rig.module.model.actions.copy(rig.module.model.entries[0].id)
        #expect(collapsed == 0)
        rig.module.stop()
    }

    @Test("History is saved on stop and comes back on the next start")
    func persistence() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.module.start()
        rig.pasteboard.copy("remember me")
        poll(rig)
        rig.module.model.actions.togglePin(rig.module.model.entries[0].id)
        rig.module.stop()
        #expect(rig.store.load().map(\.text) == ["remember me"])

        let second = makeRig(directory: rig.store.directory)
        second.module.start()
        #expect(second.module.model.entries.map(\.text) == ["remember me"])
        #expect(second.module.model.entries[0].isPinned)
        second.module.stop()
    }

    @Test("Clear on quit empties the history except pins")
    func clearOnQuit() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.settings.clipboard.clearOnQuit = true
        rig.module.start()
        rig.pasteboard.copy("keep")
        poll(rig)
        rig.module.model.actions.togglePin(rig.module.model.entries[0].id)
        rig.pasteboard.copy("drop")
        poll(rig)
        rig.module.send(.quit)
        #expect(rig.module.model.entries.map(\.text) == ["keep"])
        rig.module.stop()
    }

    @Test("Changing the length in settings trims the history")
    func settingsChange() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.module.start()
        for index in 1...60 {
            rig.pasteboard.copy("item \(index)")
            poll(rig)
        }
        #expect(rig.module.model.entries.count == 60)
        rig.settings.clipboard.historyLength = 50
        rig.module.settingsChanged()
        #expect(rig.module.model.entries.count == 50)
        rig.module.stop()
    }

    @Test("Showing the history asks the island to open the Clipboard tab with focus")
    func showHistory() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        var requests: [(String, Bool)] = []
        rig.commands.showTab = { requests.append(($0, $1)) }
        rig.module.start()
        rig.module.showHistory()
        #expect(requests.count == 1 && requests[0].0 == "clipboard" && requests[0].1)
        #expect(rig.module.menuItems().count == 1)
        rig.module.stop()
    }

    @Test("Switching it on and off five times leaves nothing registered")
    func neverLeaks() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        for _ in 0..<5 {
            rig.module.start()
            rig.pasteboard.copy("x")
            poll(rig)
            rig.module.stop()
            #expect(rig.scheduler.registrationCount == 0)
            #expect(rig.coordinator.moduleTabs.isEmpty)
            #expect(rig.module.model.entries.isEmpty)
        }
    }

    @Test("Events after stopping do nothing")
    func stoppedIgnoresEvents() {
        let rig = makeRig()
        defer { try? FileManager.default.removeItem(at: rig.store.directory) }
        rig.module.start()
        rig.module.stop()
        rig.pasteboard.copy("late")
        poll(rig)
        #expect(rig.pasteboard.reads == 0)
        #expect(rig.module.model.entries.isEmpty)
    }
}
