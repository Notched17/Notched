// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit.ps

/// Reports AC power, battery or Low Power Mode, from IOKit power-source
/// notifications and the Low Power Mode notification. No polling.
@MainActor
final class PowerStateMonitor {
    private(set) var state: PowerState = .ac
    var onChange: (PowerState) -> Void = { _ in }

    private let observers = NotificationTokens()
    private var runLoopSource: CFRunLoopSource?

    func start() {
        observers.observe(.NSProcessInfoPowerStateDidChange) { [weak self] in self?.refresh() }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerStateMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        refresh()
    }

    func stop() {
        observers.invalidate()
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
    }

    private func refresh() {
        let newState: PowerState
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            newState = .lowPower
        } else if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?,
                  type == kIOPMBatteryPowerKey {
            newState = .battery
        } else {
            newState = .ac
        }
        guard newState != state else { return }
        state = newState
        Log.scheduler.info("Power state: \(String(describing: newState), privacy: .public)")
        onChange(newState)
    }
}
