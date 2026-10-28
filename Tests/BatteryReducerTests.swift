// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Charging and low-battery banners, and the opt-in charging activity (#26).
@Suite("BatteryReducer")
struct BatteryReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 40_000)

    private func snapshot(_ power: PowerSnapshot.Power, _ level: Int) -> PowerSnapshot {
        PowerSnapshot(level: level, power: power)
    }

    /// A reducer that has already seen `power` at `level`.
    private func seeded(_ power: PowerSnapshot.Power, _ level: Int, preferences: BatteryPreferences = .init()) -> BatteryReducer {
        var sut = BatteryReducer(preferences: preferences)
        _ = sut.reduce(.snapshot(snapshot(power, level)), now: t0 - 100)
        return sut
    }

    // MARK: Full

    @Test("Full is announced once per plug-in, not on every top-off while left plugged in")
    func chargedOncePerPlugIn() {
        var sut = seeded(.charging, 99)
        #expect(sut.reduce(.snapshot(snapshot(.charged, 100)), now: t0) == [.banner(.charged)])
        // macOS tops the battery up a few times a day.
        #expect(sut.reduce(.snapshot(snapshot(.charging, 99)), now: t0 + 3600).isEmpty)
        #expect(sut.reduce(.snapshot(snapshot(.charged, 100)), now: t0 + 3700).isEmpty)
        // Unplugged and plugged in again: news again.
        _ = sut.reduce(.snapshot(snapshot(.battery, 100)), now: t0 + 7200)
        _ = sut.reduce(.tick, now: t0 + 7201)
        _ = sut.reduce(.snapshot(snapshot(.charging, 97)), now: t0 + 9000)
        _ = sut.reduce(.tick, now: t0 + 9001)
        #expect(sut.reduce(.snapshot(snapshot(.charged, 100)), now: t0 + 9500) == [.banner(.charged)])
    }

    @Test("Already full at the first reading: later top-offs are silent")
    func alreadyFullAtStart() {
        var sut = seeded(.charged, 100)
        #expect(sut.reduce(.snapshot(snapshot(.charging, 99)), now: t0).isEmpty)
        #expect(sut.reduce(.snapshot(snapshot(.charged, 100)), now: t0 + 100).isEmpty)
    }

    // MARK: IOKit's description

    @Test("IOKit's battery description maps to a snapshot, including a charge limit holding it")
    func powerSourceDescription() {
        func read(_ values: [String: Any]) -> PowerSnapshot {
            PowerSourceMonitor.snapshot(from: values, adapterWatts: 70)
        }
        let held = read(["Current Capacity": 91, "Max Capacity": 100, "Power Source State": "AC Power",
                         "Is Charging": false, "Is Charged": false, "Time to Empty": 0, "Time to Full Charge": 0])
        #expect(held == PowerSnapshot(level: 91, power: .notCharging, adapterWatts: 70))
        let charging = read(["Current Capacity": 60, "Max Capacity": 100, "Power Source State": "AC Power",
                             "Is Charging": true, "Time to Full Charge": 84])
        #expect(charging == PowerSnapshot(level: 60, power: .charging, minutesToFull: 84, adapterWatts: 70))
        let onBattery = read(["Current Capacity": 4200, "Max Capacity": 5000, "Power Source State": "Battery Power",
                              "Is Charging": false, "Time to Empty": -1])
        #expect(onBattery == PowerSnapshot(level: 84, power: .battery))
        let full = read(["Current Capacity": 100, "Max Capacity": 100, "Power Source State": "AC Power", "Is Charged": true])
        #expect(full.power == .charged)
    }

    // MARK: Plugging in and out

    @Test("The first reading is silent: the charger was already there")
    func firstSnapshotIsSilent() {
        var sut = BatteryReducer()
        #expect(sut.reduce(.snapshot(snapshot(.charging, 50)), now: t0).isEmpty)
        #expect(sut.reduce(.snapshot(snapshot(.charging, 51)), now: t0 + 60).isEmpty)
    }

    @Test("Plugging in announces charging, a second later, with the level")
    func plugInAnnouncesCharging() {
        var sut = seeded(.battery, 50)
        #expect(sut.reduce(.snapshot(snapshot(.charging, 50)), now: t0) == [.wake(t0 + 1)])
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.charging(level: 50))])
    }

    @Test("A moment of not charging right after plugging in still says Charging")
    func briefNotChargingAfterPlugIn() {
        var sut = seeded(.battery, 50)
        _ = sut.reduce(.snapshot(snapshot(.notCharging, 50)), now: t0)
        _ = sut.reduce(.snapshot(snapshot(.charging, 50)), now: t0 + 0.5)
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.charging(level: 50))])
    }

    @Test("Plugged in above the charge limit says Plugged In, not Charging")
    func notChargingSaysPluggedIn() {
        var sut = seeded(.battery, 85)
        _ = sut.reduce(.snapshot(snapshot(.notCharging, 85)), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.pluggedIn(level: 85))])
    }

    @Test("Unplugging announces On Battery")
    func unplugAnnouncesOnBattery() {
        var sut = seeded(.charging, 80)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 80)), now: t0) == [.wake(t0 + 1)])
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.onBattery(level: 80))])
    }

    @Test("A connector that touches for less than a second says nothing")
    func looseConnectorIsSilent() {
        var sut = seeded(.battery, 50)
        _ = sut.reduce(.snapshot(snapshot(.charging, 50)), now: t0)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 50)), now: t0 + 0.4).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 1).isEmpty)
    }

    @Test("Plugging back in within ten seconds of the last Charging banner stays quiet")
    func replugWithinCooldownIsSilent() {
        var sut = seeded(.battery, 50)
        _ = sut.reduce(.snapshot(snapshot(.charging, 50)), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.charging(level: 50))])
        _ = sut.reduce(.snapshot(snapshot(.battery, 50)), now: t0 + 3)
        #expect(sut.reduce(.tick, now: t0 + 4) == [.banner(.onBattery(level: 50))])
        _ = sut.reduce(.snapshot(snapshot(.charging, 50)), now: t0 + 5)
        #expect(sut.reduce(.tick, now: t0 + 6).isEmpty)
    }

    // MARK: Full

    @Test("Reaching full while plugged in is announced once")
    func fullAnnouncedOnce() {
        var sut = seeded(.charging, 99)
        #expect(sut.reduce(.snapshot(snapshot(.charged, 100)), now: t0) == [.banner(.charged)])
        #expect(sut.reduce(.snapshot(snapshot(.charged, 100)), now: t0 + 60).isEmpty)
    }

    @Test("Plugging in when already full says Fully Charged, once")
    func plugInWhenFull() {
        var sut = seeded(.battery, 100)
        #expect(sut.reduce(.snapshot(snapshot(.charged, 100)), now: t0) == [.wake(t0 + 1)])
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.charged)])
    }

    // MARK: Low battery

    @Test("Each low threshold fires once as the level crosses it")
    func lowFiresOncePerCrossing() {
        var sut = seeded(.battery, 25)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 21)), now: t0).isEmpty)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 20)), now: t0 + 60) == [.banner(.low(level: 20))])
        #expect(sut.reduce(.snapshot(snapshot(.battery, 19)), now: t0 + 120).isEmpty)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 10)), now: t0 + 600) == [.banner(.low(level: 10))])
    }

    @Test("A level jittering around the threshold fires once, until it's 3 % above it again")
    func jitterAtThresholdFiresOnce() {
        var sut = seeded(.battery, 22)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 20)), now: t0) == [.banner(.low(level: 20))])
        for (index, level) in [21, 20, 22, 20].enumerated() {
            #expect(sut.reduce(.snapshot(snapshot(.battery, level)), now: t0 + Double(index + 1) * 30).isEmpty)
        }
        _ = sut.reduce(.snapshot(snapshot(.battery, 23)), now: t0 + 200)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 20)), now: t0 + 300) == [.banner(.low(level: 20))])
    }

    @Test("Dropping past two thresholds at once fires one banner")
    func bigDropFiresOnlyLowest() {
        var sut = seeded(.battery, 25)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 9)), now: t0) == [.banner(.low(level: 9))])
        #expect(sut.reduce(.snapshot(snapshot(.battery, 8)), now: t0 + 60).isEmpty)
    }

    @Test("Starting below a threshold doesn't announce it; the next one still fires")
    func startingBelowThresholdIsSilent() {
        var sut = seeded(.battery, 15)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 14)), now: t0).isEmpty)
        #expect(sut.reduce(.snapshot(snapshot(.battery, 10)), now: t0 + 60) == [.banner(.low(level: 10))])
    }

    @Test("Thresholds are configurable")
    func customThresholds() {
        var sut = seeded(.battery, 40, preferences: BatteryPreferences(lowThresholds: [30]))
        #expect(sut.reduce(.snapshot(snapshot(.battery, 30)), now: t0) == [.banner(.low(level: 30))])
        #expect(sut.reduce(.snapshot(snapshot(.battery, 20)), now: t0 + 60).isEmpty)
    }

    // MARK: Charging activity

    @Test("The charging activity shows only when opted in, while charging below the limit")
    func activityOnlyWhenOptedInAndBelowLimit() {
        var plain = BatteryReducer()
        #expect(plain.reduce(.snapshot(snapshot(.charging, 50)), now: t0).isEmpty)

        var sut = BatteryReducer(preferences: BatteryPreferences(showWhileChargingUntil: 80))
        #expect(sut.reduce(.snapshot(snapshot(.charging, 50)), now: t0) == [.post(snapshot(.charging, 50))])
        #expect(sut.reduce(.snapshot(snapshot(.charging, 79)), now: t0 + 60) == [.post(snapshot(.charging, 79))])
        #expect(sut.reduce(.snapshot(snapshot(.charging, 80)), now: t0 + 120) == [.end])
        #expect(sut.reduce(.snapshot(snapshot(.charging, 81)), now: t0 + 180).isEmpty)
    }

    @Test("Unplugging ends the charging activity")
    func unplugEndsActivity() {
        var sut = seeded(.charging, 50, preferences: BatteryPreferences(showWhileChargingUntil: 100))
        #expect(sut.reduce(.snapshot(snapshot(.battery, 50)), now: t0) == [.wake(t0 + 1), .end])
    }

    @Test("Turning the activity setting off ends it; on posts it")
    func preferencesChangeActivity() {
        var sut = seeded(.charging, 50, preferences: BatteryPreferences(showWhileChargingUntil: 80))
        #expect(sut.reduce(.preferences(BatteryPreferences()), now: t0) == [.end])
        #expect(sut.reduce(.preferences(BatteryPreferences(showWhileChargingUntil: 100)), now: t0 + 1)
            == [.post(snapshot(.charging, 50))])
    }

    @Test("A Mac without a battery shows nothing at all")
    func noBatteryDoesNothing() {
        var sut = BatteryReducer(preferences: BatteryPreferences(showWhileChargingUntil: 100))
        let desktop = PowerSnapshot(hasBattery: false, level: 0, power: .charged)
        #expect(sut.reduce(.snapshot(desktop), now: t0).isEmpty)
        #expect(sut.reduce(.snapshot(desktop), now: t0 + 60).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 61).isEmpty)
    }
}
