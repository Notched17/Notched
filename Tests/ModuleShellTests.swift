// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit.pwr_mgt
import Testing
@testable import Notched

/// Counts acquires and releases instead of touching the power manager.
@MainActor
final class FakePowerAssertion: PowerAssertionClient {
    private(set) var isHeld = false
    private(set) var acquires = 0
    private(set) var releases = 0
    var refuses = false

    func acquire(reason: String) -> Bool {
        guard !refuses else { return false }
        if !isHeld { acquires += 1 }
        isHeld = true
        return true
    }

    func release() {
        if isHeld { releases += 1 }
        isHeld = false
    }
}

/// The M3a module shells leave nothing behind: no assertion, run-loop
/// source, registry notification, event monitor, path monitor or CoreAudio
/// listener outlives `stop()`, however often they're switched on and off.
@MainActor
@Suite("Module shells")
struct ModuleShellTests {
    private func context(_ id: ModuleID, services: ModuleServices = ModuleServices()) -> (ModuleContext, ActivityCoordinator) {
        let coordinator = ActivityCoordinator()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "ModuleShellTests.\(UUID().uuidString)")!)
        let context = ModuleContext(activities: ActivitySink(moduleID: id, coordinator: coordinator), scheduler: RefreshScheduler(),
                                    settings: settings, services: services, previousSessionCrashed: false)
        return (context, coordinator)
    }

    // MARK: Keep Awake

    @Test("Keep Awake holds one assertion however it's used, and stopping releases it")
    func keepAwakeNeverLeaks() {
        let fake = FakePowerAssertion()
        let (context, coordinator) = context(KeepAwakeModule.descriptor.id)
        for _ in 0..<5 {
            let module = KeepAwakeModule(context: context, assertion: fake)
            module.start()
            module.turnOn(.oneHour)
            module.turnOn(.indefinitely)
            module.turnOn(.thirtyMinutes)
            #expect(fake.isHeld)
            #expect(coordinator.live.map(\.id) == [KeepAwakeModule.activityID])
            module.stop()
            #expect(!fake.isHeld)
            #expect(coordinator.live.isEmpty)
            #expect(coordinator.homeActions.isEmpty)
        }
        #expect(fake.acquires == 5)
        #expect(fake.releases == 5)
    }

    @Test("Turning Keep Awake off releases the assertion and ends the activity")
    func keepAwakeTurnOff() {
        let fake = FakePowerAssertion()
        let (context, coordinator) = context(KeepAwakeModule.descriptor.id)
        let module = KeepAwakeModule(context: context, assertion: fake)
        module.start()
        module.turnOn(.twoHours)
        module.turnOff()
        #expect(!fake.isHeld)
        #expect(coordinator.live.isEmpty)
        #expect(coordinator.recent.isEmpty)
        #expect(coordinator.homeActions.map(\.isOn) == [false])
        module.stop()
    }

    @Test("Keep Awake refused by macOS ends without holding anything")
    func keepAwakeRefused() {
        let fake = FakePowerAssertion()
        fake.refuses = true
        let (context, coordinator) = context(KeepAwakeModule.descriptor.id)
        let module = KeepAwakeModule(context: context, assertion: fake)
        module.start()
        module.turnOn(.oneHour)
        #expect(!fake.isHeld)
        #expect(coordinator.live.isEmpty)
        #expect(module.model.isOn == false)
        module.stop()
    }

    @Test("The real assertion shows up for this process, and goes when released")
    func realAssertionIsReleased() {
        let client = IOPMPowerAssertionClient()
        let reason = "Notched test \(UUID().uuidString)"
        #expect(client.acquire(reason: reason))
        #expect(client.acquire(reason: reason))
        #expect(Self.assertions(named: reason) == 1)
        client.release()
        client.release()
        #expect(Self.assertions(named: reason) == 0)
    }

    /// This process's power assertions with this name, as `pmset -g assertions` lists them.
    private static func assertions(named name: String) -> Int {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return -1 }
        let mine = all[NSNumber(value: getpid())] ?? []
        return mine.filter { $0[kIOPMAssertionNameKey] as? String == name }.count
    }

    // MARK: System sources

    @Test("The power-source run-loop source comes and goes with the monitor")
    func powerMonitorStops() {
        let monitor = PowerSourceMonitor()
        for _ in 0..<5 {
            var readings = 0
            monitor.onChange = { _ in readings += 1 }
            monitor.start()
            monitor.start()
            #expect(monitor.isRunning)
            #expect(readings == 1)
            monitor.stop()
            #expect(!monitor.isRunning)
        }
    }

    @Test("Bluetooth accessory notifications come and go with the monitor")
    func accessoryMonitorStops() {
        let monitor = BluetoothHIDMonitor()
        for _ in 0..<5 {
            monitor.start()
            #expect(monitor.isRunning)
            monitor.stop()
            #expect(!monitor.isRunning)
        }
    }

    @Test("Bluetooth and Now Playing share CoreAudio listeners, and the last one out removes them")
    func sharedAudioListeners() {
        let services = ModuleServices()
        let outputs = services.audioOutputs
        let (context, _) = context(BluetoothModule.descriptor.id, services: services)
        for _ in 0..<5 {
            let bluetooth = BluetoothModule(context: context)
            bluetooth.start()
            let listening = outputs.listenerCount
            #expect(listening > 0)
            outputs.acquire()  // Now Playing, say
            #expect(outputs.listenerCount == listening)
            bluetooth.stop()
            #expect(outputs.listenerCount == listening)
            outputs.release()
            #expect(outputs.listenerCount == 0)
        }
    }

    @Test("Camera & Microphone leaves no listener, observer or activity behind when it stops, however often it is switched")
    func sensorsNeverLeak() {
        let services = ModuleServices()
        let (context, coordinator) = context(SensorsModule.descriptor.id, services: services)
        for _ in 0..<5 {
            let module = SensorsModule(context: context)
            module.start()
            services.sensors.flush()
            #expect(module.isRunning)
            #expect(services.sensors.listenerCount > 0)
            module.stop()
            services.sensors.flush()
            #expect(!module.isRunning)
            #expect(services.sensors.listenerCount == 0)
            #expect(coordinator.live.isEmpty)
        }
    }

    @Test("Camera & Microphone and Calls share one set of listeners; the last holder out removes them")
    func sensorsAreShared() {
        let services = ModuleServices()
        let (context, _) = context(SensorsModule.descriptor.id, services: services)
        let module = SensorsModule(context: context)
        module.start()
        services.sensors.acquire()  // Calls, say
        services.sensors.flush()
        let installed = services.sensors.listenerCount
        #expect(installed > 0)
        module.stop()
        services.sensors.flush()
        #expect(services.sensors.listenerCount == installed)
        services.sensors.release()
        services.sensors.flush()
        #expect(services.sensors.listenerCount == 0)
    }

    @Test("Calls leaves no listener, observer, claim or activity behind when it stops, however often it is switched")
    func callsNeverLeak() {
        let services = ModuleServices()
        let (context, coordinator) = context(CallsModule.descriptor.id, services: services)
        for _ in 0..<5 {
            let module = CallsModule(context: context)
            module.start()
            services.sensors.flush()
            #expect(module.isRunning)
            #expect(services.sensors.listenerCount > 0)
            module.stop()
            services.sensors.flush()
            #expect(!module.isRunning)
            #expect(services.sensors.listenerCount == 0)
            #expect(coordinator.live.isEmpty)
        }
    }

    @Test("A stopped Calls module can never leave the microphone indicator suppressed, even while Camera & Microphone keeps the service alive")
    func callsClaimsClearedOnStop() {
        let services = ModuleServices()
        let (context, _) = context(CallsModule.descriptor.id, services: services)
        services.sensors.acquire()  // Camera & Microphone, say
        let module = CallsModule(context: context)
        module.start()
        services.sensors.setCallClaims(CallClaims(identities: ["us.zoom.xos"], isCallActive: true))
        module.stop()
        #expect(services.sensors.callClaims == CallClaims())
        services.sensors.release()
    }

    @Test("Caps Lock's event monitors are removed when it stops")
    func capsLockStops() {
        let (context, _) = context(CapsLockModule.descriptor.id)
        for _ in 0..<5 {
            let module = CapsLockModule(context: context)
            module.start()
            #expect(module.isRunning)
            module.stop()
            #expect(!module.isRunning)
        }
    }

    @Test("Network's path monitor is cancelled when it stops")
    func networkStops() {
        let (context, _) = context(NetworkModule.descriptor.id)
        for _ in 0..<5 {
            let module = NetworkModule(context: context)
            module.start()
            #expect(module.isMonitoring)
            module.stop()
            #expect(!module.isMonitoring)
        }
    }

    // MARK: Timers

    @Test("A running timer survives the module stopping and starting again, as across a relaunch")
    func timersSurviveRelaunch() {
        let (context, coordinator) = context(TimersModule.descriptor.id)
        let first = TimersModule(context: context)
        first.start()
        first.startTimer(seconds: 600, label: "Tea")
        #expect(coordinator.live.map(\.activity.title) == ["Tea"])
        #expect(coordinator.homeActions.map(\.isOn) == [true])
        first.stop()
        #expect(coordinator.live.isEmpty)
        #expect(coordinator.homeActions.isEmpty)
        #expect(context.settings.timers.savedState?.timers.map(\.label) == ["Tea"])

        let second = TimersModule(context: context)
        second.start()
        #expect(coordinator.live.map(\.activity.title) == ["Tea"])
        second.stop()
    }

    @Test("Cancelling the last timer clears what's saved")
    func cancelClearsSavedState() {
        let (context, coordinator) = context(TimersModule.descriptor.id)
        let module = TimersModule(context: context)
        module.start()
        module.startTimer(seconds: 60)
        guard let id = module.model.state.timers.first?.id else {
            Issue.record("No timer started")
            return
        }
        module.model.actions.cancel(id)
        #expect(coordinator.live.isEmpty)
        #expect(coordinator.recent.isEmpty)
        #expect(context.settings.timers.savedState == nil)
        module.stop()
    }

    @Test("The soonest-ending timer ranks first, and a newer, sooner one takes over")
    func soonestTimerRanksFirst() {
        let (context, coordinator) = context(TimersModule.descriptor.id)
        let module = TimersModule(context: context)
        module.start()
        module.startTimer(seconds: 600, label: "Long")
        module.startTimer(seconds: 60, label: "Short")
        #expect(coordinator.primary?.activity.title == "Short")
        module.stop()
    }

    // MARK: Banners

    @Test("A long Bluetooth name loses the owner's name")
    func bluetoothDisplayName() {
        #expect(BluetoothDevice.displayName("Charlie’s AirPods Pro") == "AirPods Pro")
        #expect(BluetoothDevice.displayName("Charlie's Magic Keyboard") == "Magic Keyboard")
        #expect(BluetoothDevice.displayName("BluetoothMouse3600") == "BluetoothMouse3600")
        #expect(BluetoothDevice.displayName("  Bose QC35 II ") == "Bose QC35 II")
        #expect(BluetoothDevice.displayName("Let's go") == "Let's go")
    }
}
