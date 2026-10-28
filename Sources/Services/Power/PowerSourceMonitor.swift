// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit.ps

/// The Mac's battery and charger, from IOKit's power-source info (#26).
/// Event-driven: IOKit calls back on the main run loop whenever a power
/// source changes, so there's no polling. Exists only while Battery runs.
@MainActor
final class PowerSourceMonitor {
    var onChange: (PowerSnapshot) -> Void = { _ in }
    private var source: CFRunLoopSource?
    private let log = Log.module("battery")

    /// True while IOKit's run-loop source is installed (tests check `stop()` removes it).
    var isRunning: Bool { source != nil }

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().changed()
            }
        }, context)?.takeRetainedValue() else {
            log.error("Couldn't watch power sources")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        source = created
        changed()
    }

    /// The run-loop source holds an unretained pointer to this monitor.
    isolated deinit {
        stop()
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        self.source = nil
    }

    private func changed() {
        onChange(Self.read())
    }

    /// The internal battery right now; `hasBattery` is false on a desktop Mac.
    nonisolated static func read() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else {
            return PowerSnapshot(hasBattery: false, level: 0, power: .battery)
        }
        for source in list as NSArray as [AnyObject] {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool ?? true else { continue }
            return snapshot(from: description, adapterWatts: adapterWatts())
        }
        return PowerSnapshot(hasBattery: false, level: 0, power: .battery)
    }

    /// Maps one battery's description (keys from IOPSKeys.h). With a charge
    /// limit or Optimised Charging, macOS reports AC power, not charging and
    /// not charged: that's `.notCharging` ("Plugged In").
    nonisolated static func snapshot(from description: [String: Any], adapterWatts: Int?) -> PowerSnapshot {
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
        let level = min(max(Int((Double(current) * 100 / Double(maximum)).rounded()), 0), 100)
        let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let charged = description[kIOPSIsChargedKey] as? Bool ?? false
        let power: PowerSnapshot.Power = if !onAC {
            .battery
        } else if charging {
            .charging
        } else if charged || level >= 100 {
            .charged
        } else {
            .notCharging
        }
        // IOKit says -1 while it's still estimating, and 0 when it doesn't apply.
        let minutes = { (key: String) -> Int? in (description[key] as? Int).flatMap { $0 > 0 ? $0 : nil } }
        return PowerSnapshot(
            hasBattery: true,
            level: level,
            power: power,
            minutesToEmpty: power == .battery ? minutes(kIOPSTimeToEmptyKey) : nil,
            minutesToFull: power == .charging ? minutes(kIOPSTimeToFullChargeKey) : nil,
            adapterWatts: onAC ? adapterWatts : nil
        )
    }

    private nonisolated static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = details[kIOPSPowerAdapterWattsKey] as? Int, watts > 0 else { return nil }
        return watts
    }
}
