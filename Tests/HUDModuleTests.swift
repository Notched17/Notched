// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing
@testable import Notched

/// Records the calls the module makes, in order, and can refuse to install.
final class FakeTap: MediaKeyTapping, @unchecked Sendable {
    private(set) var log: [String] = []
    private let installResult: Bool
    private var installed = false

    init(installResult: Bool = true) {
        self.installResult = installResult
    }

    func install() -> Bool {
        log.append("install")
        installed = installResult
        return installResult
    }

    func setEnabled(_ enabled: Bool) { log.append("setEnabled(\(enabled))") }

    func remove() {
        log.append("remove")
        installed = false
    }

    var isInstalled: Bool { installed }
}

/// A module wired to fakes: a tap that records, a permission check that can be flipped.
@MainActor
private final class Rig {
    final class Bag {
        var taps: [FakeTap] = []
        var engines: [HUDKeyEngine] = []
        var installResult = true
        var trusted: Bool
        init(trusted: Bool) { self.trusted = trusted }
    }

    let bag: Bag
    let settings: SettingsStore
    let coordinator = ActivityCoordinator()
    let presence = IslandPresence()
    let services: ModuleServices
    let module: HUDModule

    var taps: [FakeTap] { bag.taps }

    init(trusted: Bool = true, previousSessionCrashed: Bool = false, judgesLaunch: Bool = false,
         prepare: (HUDSettings) -> Void = { _ in }) {
        let bag = Bag(trusted: trusted)
        self.bag = bag
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "HUDModuleTests.\(UUID().uuidString)")!)
        self.settings = settings
        prepare(settings.hud)
        let services = ModuleServices(presence: presence)
        self.services = services
        let context = ModuleContext(
            activities: ActivitySink(moduleID: HUDModule.descriptor.id, coordinator: coordinator), scheduler: RefreshScheduler(),
            settings: settings, services: services, previousSessionCrashed: previousSessionCrashed
        )
        module = HUDModule(
            context: context,
            makeTap: { engine in
                let tap = FakeTap(installResult: bag.installResult)
                bag.taps.append(tap)
                bag.engines.append(engine)
                return tap
            },
            trustCheck: { bag.trusted },
            judgesLaunch: judgesLaunch
        )
        presence.anyIslandShown = true
    }

    /// Lets the observation and delivery hops run.
    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor
@Suite("HUDModule")
struct HUDModuleTests {
    private let latch = HUDLatch(reason: .timeouts, date: Date(timeIntervalSince1970: 1_000))

    @Test("It arms when Accessibility is allowed, and says so")
    func startsArmedWhenTrusted() {
        let rig = Rig()
        rig.module.start()
        #expect(rig.taps.count == 1)
        #expect(rig.taps[0].log.first == "install")
        #expect(rig.module.status == .running)
        #expect(rig.settings.hud.armedSession == true)
        rig.module.stop()
    }

    @Test("Without Accessibility no tap is made, and the status says Not Allowed")
    func doesNotInstallWithoutTrust() {
        let rig = Rig(trusted: false)
        rig.module.start()
        #expect(rig.taps.isEmpty)
        #expect(rig.module.status == .notAllowed)
        rig.module.stop()
    }

    @Test("A tap the system refuses is not kept, and nothing is left armed")
    func refusedTapIsNotKept() {
        let rig = Rig()
        rig.bag.installResult = false
        rig.module.start()
        #expect(rig.taps.count == 1)
        #expect(!rig.module.isArmed)
        #expect(rig.module.status == .notAllowed)
        #expect(rig.settings.hud.armedSession == false)
        rig.module.stop()
    }

    @Test("A latched HUD starts without a tap")
    func doesNotInstallWhenLatched() {
        let rig = Rig { $0.latch = latch }
        rig.module.start()
        #expect(rig.taps.isEmpty)
        #expect(rig.module.status == .latched(latch))
        rig.module.stop()
    }

    @Test("A paused HUD starts without a tap")
    func doesNotInstallWhenPaused() {
        let rig = Rig { $0.isPaused = true }
        rig.module.start()
        #expect(rig.taps.isEmpty)
        #expect(rig.module.status == .paused)
        rig.module.stop()
    }

    @Test("Pausing disarms the engine first, then switches the tap off, then removes it")
    func pauseDisarmsBeforeTeardown() {
        let rig = Rig()
        rig.module.start()
        rig.module.setPaused(true)
        #expect(Array(rig.taps[0].log.suffix(2)) == ["setEnabled(false)", "remove"])
        // The engine that was running now lets every key through.
        let key = MediaKeyEvent(key: .soundUp, phase: .down, isRepeat: false, modifiers: [])
        #expect(rig.bag.engines[0].handle(key) == .pass)
        #expect(rig.module.status == .paused)
        #expect(rig.settings.hud.isPaused == true)
        #expect(rig.settings.hud.armedSession == false)
        rig.module.stop()
    }

    @Test("Turning it back on clears the latch and arms again")
    func turnBackOnClearsLatch() {
        let rig = Rig { $0.latch = latch; $0.uncleanStreak = 2 }
        rig.module.start()
        rig.module.turnBackOn()
        #expect(rig.settings.hud.latch == nil)
        #expect(rig.settings.hud.uncleanStreak == 0)
        #expect(rig.taps.count == 1)
        #expect(rig.module.status == .running)
        rig.module.stop()
    }

    @Test("Losing Accessibility removes the tap without a latch, and getting it back arms again")
    func trustLossRemovesAndReinstallsOnReturn() {
        let rig = Rig()
        rig.module.start()
        rig.bag.trusted = false
        rig.module.checkTrust()
        #expect(rig.taps[0].log.last == "remove")
        #expect(rig.module.status == .notAllowed)
        #expect(rig.settings.hud.latch == nil)
        rig.bag.trusted = true
        rig.module.checkTrust()
        #expect(rig.taps.count == 2)
        #expect(rig.module.status == .running)
        rig.module.stop()
    }

    @Test("A second timeout removes the tap, persists the latch, and says so once")
    func timeoutsLatchAndPersist() {
        let rig = Rig()
        rig.module.start()
        let engine = rig.bag.engines[0]
        #expect(engine.tapDisabled(byTimeout: true, trusted: true) == .reEnable)
        #expect(engine.tapDisabled(byTimeout: true, trusted: true) == .remove(.timeouts))
        #expect(rig.taps[0].log.last == "remove")
        #expect(rig.settings.hud.latch?.reason == .timeouts)
        #expect(rig.module.status == .latched(rig.settings.hud.latch!))
        #expect(rig.coordinator.banner?.id == "hud.latched")
        rig.module.stop()
    }

    @Test("Pause Island or a locked screen switches the tap off, without removing it")
    func suspendedDisablesTap() async {
        let rig = Rig()
        rig.module.start()
        rig.presence.isSuspended = true
        await rig.settle()
        #expect(rig.taps[0].log.last == "setEnabled(false)")
        rig.presence.isSuspended = false
        await rig.settle()
        #expect(rig.taps[0].log.last == "setEnabled(true)")
        #expect(!rig.taps[0].log.contains("remove"))
        rig.module.stop()
    }

    @Test("Switching it on and off ten times leaves no tap, flag, or output listener behind")
    func startStopTenTimesLeavesNothing() {
        let rig = Rig()
        for _ in 0..<10 {
            rig.module.start()
            #expect(rig.module.isArmed)
            rig.module.stop()
            #expect(!rig.module.isArmed)
        }
        #expect(rig.taps.count == 10)
        #expect(rig.taps.allSatisfy { !$0.isInstalled })
        #expect(rig.settings.hud.armedSession == false)
        #expect(rig.services.audioOutputs.listenerCount == 0)
    }

    @Test("Two sessions in a row that crashed while armed start latched")
    func secondArmedCrashStartsLatched() {
        let rig = Rig(previousSessionCrashed: true, judgesLaunch: true) { $0.armedSession = true; $0.uncleanStreak = 1 }
        rig.module.start()
        #expect(rig.taps.isEmpty)
        if case .latched(let latch) = rig.module.status { #expect(latch.reason == .uncleanExits) } else { Issue.record("not latched") }
        rig.module.stop()
    }

    @Test("The first armed crash only counts; the HUD still arms")
    func firstArmedCrashStillArms() {
        let rig = Rig(previousSessionCrashed: true, judgesLaunch: true) { $0.armedSession = true }
        rig.module.start()
        #expect(rig.settings.hud.uncleanStreak == 1)
        #expect(rig.module.status == .running)
        rig.module.stop()
    }

    @Test("A session killed under a debugger isn't a crash")
    func debuggerKillIsNotACrash() {
        let rig = Rig(previousSessionCrashed: false, judgesLaunch: true) { $0.armedSession = true; $0.uncleanStreak = 1 }
        rig.module.start()
        #expect(rig.settings.hud.uncleanStreak == 0)
        #expect(rig.module.status == .running)
        rig.module.stop()
    }

    @Test("The status menu offers Pause HUD Replacement, ticked while paused")
    func menuItemReflectsPause() {
        let rig = Rig()
        rig.module.start()
        let item = rig.module.menuItems().first
        #expect(item?.title == "Pause HUD Replacement")
        #expect(item?.state == .off)
        rig.module.setPaused(true)
        #expect(rig.module.menuItems().first?.state == .on)
        rig.module.stop()
    }
}
