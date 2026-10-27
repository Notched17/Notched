// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Knows when nobody can see the screen: displays asleep, the Mac asleep, the
/// screen locked, or another user's session active. Work pauses meanwhile.
@MainActor
final class SystemActivityMonitor {
    private(set) var isSuspended = false
    var onChange: (Bool) -> Void = { _ in }

    private var screensAsleep = false
    private var systemAsleep = false
    private var screenLocked = false
    private var sessionInactive = false
    private let observers = NotificationTokens()

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observers.observe(NSWorkspace.screensDidSleepNotification, in: workspace) { [weak self] in self?.update { $0.screensAsleep = true } }
        observers.observe(NSWorkspace.screensDidWakeNotification, in: workspace) { [weak self] in self?.update { $0.screensAsleep = false } }
        observers.observe(NSWorkspace.willSleepNotification, in: workspace) { [weak self] in self?.update { $0.systemAsleep = true } }
        observers.observe(NSWorkspace.didWakeNotification, in: workspace) { [weak self] in self?.update { $0.systemAsleep = false } }
        observers.observe(NSWorkspace.sessionDidResignActiveNotification, in: workspace) { [weak self] in self?.update { $0.sessionInactive = true } }
        observers.observe(NSWorkspace.sessionDidBecomeActiveNotification, in: workspace) { [weak self] in self?.update { $0.sessionInactive = false } }
        observers.observe(Notification.Name("com.apple.screenIsLocked"), in: distributed) { [weak self] in self?.update { $0.screenLocked = true } }
        observers.observe(Notification.Name("com.apple.screenIsUnlocked"), in: distributed) { [weak self] in self?.update { $0.screenLocked = false } }
    }

    func stop() {
        observers.invalidate()
    }

    private func update(_ change: (SystemActivityMonitor) -> Void) {
        change(self)
        let suspended = screensAsleep || systemAsleep || screenLocked || sessionInactive
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        Log.scheduler.info("Work \(suspended ? "paused" : "resumed", privacy: .public) (screens asleep, locked or inactive session)")
        onChange(suspended)
    }
}
