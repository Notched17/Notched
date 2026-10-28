// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Records what happens to the host's test modules. Separate from
/// `ModuleEventLog`, because these tests suspend and suites run in parallel.
@MainActor
final class HostEventLog {
    static let shared = HostEventLog()
    var events: [String] = []
}

@MainActor
class HostTestModule {
    let context: ModuleContext
    class var name: String { "" }
    required init(context: ModuleContext) {
        self.context = context
        HostEventLog.shared.events.append("\(Self.name).init")
    }
    func start() { HostEventLog.shared.events.append("\(Self.name).start") }
    func stop() { HostEventLog.shared.events.append("\(Self.name).stop") }
}

@MainActor
final class FirstHostModule: HostTestModule, IslandModule {
    static let descriptor = ModuleDescriptor(id: "first", name: "First", symbol: "1.circle", summary: "", permissions: [], isDebugOnly: false)
    override class var name: String { "first" }
}

@MainActor
final class SecondHostModule: HostTestModule, IslandModule {
    static let descriptor = ModuleDescriptor(id: "second", name: "Second", symbol: "2.circle", summary: "", permissions: [], isDebugOnly: false)
    override class var name: String { "second" }
}

/// Reads a setting while starting, as real modules do.
@MainActor
final class ReaderHostModule: HostTestModule, IslandModule {
    static let descriptor = ModuleDescriptor(id: "reader", name: "Reader", symbol: "eye", summary: "", permissions: [], isDebugOnly: false)
    override class var name: String { "reader" }
    override func start() {
        _ = context.settings.hapticsEnabled
        super.start()
    }
}

@MainActor
final class DefaultOnHostModule: HostTestModule, IslandModule {
    static let descriptor = ModuleDescriptor(id: "defaulton", name: "Default On", symbol: "power", summary: "", permissions: [],
                                             isDebugOnly: false, isOnByDefault: true)
    override class var name: String { "defaulton" }
}

@Suite("ModuleHost", .serialized)
@MainActor
struct ModuleHostTests {
    let coordinator = ActivityCoordinator()
    let now = Date(timeIntervalSinceReferenceDate: 50_000)

    private func makeHost(_ types: [any IslandModule.Type] = [FirstHostModule.self, SecondHostModule.self],
                          configure: (SettingsStore) -> Void = { _ in }) -> (ModuleHost, SettingsStore) {
        HostEventLog.shared.events.removeAll()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "ModuleHostTests.\(UUID().uuidString)")!)
        configure(settings)
        let now = now
        let host = ModuleHost(moduleTypes: types, coordinator: coordinator, settings: settings, scheduler: RefreshScheduler(),
                              services: ModuleServices(), now: { now })
        return (host, settings)
    }

    private var events: [String] { HostEventLog.shared.events }

    /// Lets the host's observation hop (a main-actor task) run.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test("Modules start in catalogue order, whatever order they were enabled in")
    func startsInCatalogOrder() {
        let (host, _) = makeHost { $0.enabledModules = ["second", "first"] }
        host.start(debuggerAttached: false)
        #expect(events == ["first.init", "first.start", "second.init", "second.start"])
        #expect(host.runningIDs == ["first", "second"])
    }

    @Test("Quitting stops modules newest first and records a clean exit")
    func stopsInReverseStartOrderOnShutDown() {
        let (host, settings) = makeHost { $0.enabledModules = ["first", "second"] }
        host.start(debuggerAttached: false)
        #expect(settings.launchRecord.sessionOpen)
        host.shutDown()
        #expect(Array(events.suffix(2)) == ["second.stop", "first.stop"])
        #expect(!settings.launchRecord.sessionOpen)
        #expect(host.runningIDs.isEmpty)
    }

    @Test("One change stops the old module before starting the new one")
    func oneReconcileStopsBeforeStarting() {
        let (host, _) = makeHost()
        host.reconcile(enabled: ["first"])
        host.reconcile(enabled: ["second"])
        #expect(Array(events.suffix(3)) == ["first.stop", "second.init", "second.start"])
    }

    @Test("Turning a module off and on again makes a fresh instance")
    func reEnableMakesAFreshInstance() throws {
        let (host, _) = makeHost()
        host.reconcile(enabled: ["first"])
        let before = try #require(host.module("first"))
        host.reconcile(enabled: [])
        #expect(host.module("first") == nil)
        host.reconcile(enabled: ["first"])
        let after = try #require(host.module("first"))
        #expect(ObjectIdentifier(before) != ObjectIdentifier(after))
        #expect(events.filter { $0 == "first.init" }.count == 2)
    }

    @Test("A setting a module reads while starting doesn't restart or re-run anything")
    func readingSettingsInStartDoesNotReconcileAgain() async {
        let (host, settings) = makeHost([ReaderHostModule.self]) { $0.enabledModules = ["reader"] }
        host.start(debuggerAttached: false)
        let passes = host.observationPasses
        settings.hapticsEnabled.toggle()
        await settle()
        #expect(host.observationPasses == passes)
        #expect(events == ["reader.init", "reader.start"])
    }

    @Test("The host follows the enabled-modules setting")
    func enabledChangeIsObserved() async {
        let (host, settings) = makeHost { $0.enabledModules = ["first"] }
        host.start(debuggerAttached: false)
        let passes = host.observationPasses
        settings.enabledModules = ["second"]
        await settle()
        #expect(host.observationPasses == passes + 1)
        #expect(Array(events.suffix(3)) == ["first.stop", "second.init", "second.start"])
        #expect(host.runningIDs == ["second"])
    }

    @Test("A module that crashed while starting twice is suspended until resumed")
    func crashMarkerSuspendsAfterTwoStrikes() {
        let (host, settings) = makeHost {
            $0.enabledModules = ["first", "second"]
            $0.launchRecord = LaunchRecord(sessionOpen: true, startingModule: "first", strikes: ["first": 1])
        }
        host.start(debuggerAttached: false)
        #expect(host.previousSessionCrashed)
        #expect(host.suspendedIDs == ["first"])
        #expect(host.runningIDs == ["second"])
        #expect(settings.enabledModules.contains("first"))
        host.resume("first")
        #expect(host.runningIDs == ["first", "second"])
        #expect(settings.launchRecord.suspended.isEmpty)
    }

    @Test("Safe mode starts no module until the user resumes")
    func safeModeStartsNothing() {
        let (host, _) = makeHost {
            $0.enabledModules = ["first"]
            $0.launchRecord = LaunchRecord(sessionOpen: true, quickCrashes: [now - 60, now - 30])
        }
        host.start(debuggerAttached: false)
        #expect(host.isSafeMode)
        #expect(host.runningIDs.isEmpty)
        host.leaveSafeMode()
        #expect(host.runningIDs == ["first"])
    }

    @Test("A module's start is bracketed in the launch record, so a crash there is attributed")
    func startIsBracketed() {
        let (host, settings) = makeHost { $0.enabledModules = ["first"] }
        host.start(debuggerAttached: false)
        #expect(settings.launchRecord.startingModule == nil)
        #expect(settings.launchRecord.sessionOpen)
    }

    @Test("Default-on modules start on first launch, once")
    func defaultOnModulesStartOnFirstLaunch() {
        let (host, settings) = makeHost([FirstHostModule.self, DefaultOnHostModule.self])
        host.start(debuggerAttached: false)
        #expect(host.runningIDs == ["defaulton"])
        #expect(settings.seenModules == ["first", "defaulton"])
    }
}
