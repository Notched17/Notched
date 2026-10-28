// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation

/// Whether the camera and microphone are in use, and by which app, shared by
/// every module that cares (Camera & Microphone, Calls). The listeners exist
/// only while a module holds the service (`acquire`/`release`), and all the
/// system work happens off the main thread in `SensorMonitor`.
@MainActor
@Observable
final class SensorUsageService {
    /// Daemons that use the microphone but that macOS itself doesn't show an
    /// indicator for. Filled in from measurements (ADR-0017); empty until then.
    static let ignoredBundleIDs: Set<String> = []

    private(set) var snapshot = SensorSnapshot.idle
    private(set) var callClaims = CallClaims()

    @ObservationIgnored private var clients = 0
    @ObservationIgnored private var monitor: SensorMonitor?
    @ObservationIgnored private let observers = NotificationTokens()

    /// CoreAudio and CoreMediaIO listeners installed now (tests check none leak).
    var listenerCount: Int { monitor?.listenerCount ?? 0 }

    /// Starts watching for the first holder.
    func acquire() {
        clients += 1
        if clients == 1 { start() }
    }

    /// Stops watching once the last holder lets go.
    func release() {
        guard clients > 0 else { return }
        clients -= 1
        if clients == 0 { stop() }
    }

    #if DEBUG
    /// Spike S1: gets the system's raw report after every look.
    func setDebugSink(_ sink: (@Sendable (String) -> Void)?) { monitor?.setDebugSink(sink) }
    #endif

    /// Waits for the monitor to finish what it was asked to do (tests).
    func flush() { monitor?.flush() }

    /// The Calls module sets this; clear it when the module stops.
    func setCallClaims(_ claims: CallClaims) {
        if claims != callClaims { callClaims = claims }
    }

    private func start() {
        let monitor = self.monitor ?? SensorMonitor { [weak self] snapshot in
            MainActor.assumeIsolated { self?.apply(snapshot) }
        }
        self.monitor = monitor
        monitor.start(apps: Self.runningApps(), ignoredBundleIDs: Self.ignoredBundleIDs)
        // The owner of a microphone stream can only be named while its app is running.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.observe(name, in: NSWorkspace.shared.notificationCenter) { [weak self] in
                self?.monitor?.updateApps(Self.runningApps())
            }
        }
    }

    private func stop() {
        observers.invalidate()
        monitor?.stop()
        snapshot = .idle
        callClaims = CallClaims()
    }

    private func apply(_ next: SensorSnapshot) {
        // A snapshot queued before `stop()` must not bring the indicator back.
        guard clients > 0, next != snapshot else { return }
        snapshot = next
    }

    private static func runningApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications.map {
            RunningAppInfo(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier,
                           name: $0.localizedName ?? $0.bundleIdentifier ?? "An app", bundlePath: $0.bundleURL?.path)
        }
    }
}
