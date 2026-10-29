// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import CoreBluetooth
import CoreGraphics
import CoreLocation
import EventKit
import IOKit.hid
import Observation

enum PermissionStatus: Equatable, Sendable {
    case granted
    /// The user said no (only where macOS can tell us).
    case denied
    case notDetermined
    /// Not granted, and macOS can't say whether it was ever asked
    /// (Accessibility, Screen Recording, Input Monitoring).
    case off
    /// Can't be known up front (Automation is granted per app, when first used).
    case perApp

    var title: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not Allowed"
        case .notDetermined: "Not Asked Yet"
        case .off: "Off"
        case .perApp: "Asked Per App"
        }
    }
}

/// Live status of every macOS privacy permission the app may use, how to ask
/// for each, and a deep link to its System Settings pane (#77).
///
/// Nothing is requested until a module that needs it is turned on. macOS
/// doesn't notify apps about TCC changes, so status refreshes when the app
/// becomes active and every 2 s while a permissions UI is on screen.
@MainActor
@Observable
final class PermissionCenter {
    static let liveUpdatesKey = "permissions"

    private(set) var statuses: [Permission: PermissionStatus] = [:]

    @ObservationIgnored private let observers = NotificationTokens()
    @ObservationIgnored private var bluetoothRequester: BluetoothRequester?
    @ObservationIgnored private var locationManager: CLLocationManager?
    @ObservationIgnored private let defaults: UserDefaults

    init(scheduler: RefreshScheduler, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
        observers.observe(NSApplication.didBecomeActiveNotification) { [weak self] in
            self?.refresh()
            self?.recheckDownloadsFolder()
        }
        scheduler.register("permissions", every: .seconds(2), when: .whileUIVisible(Self.liveUpdatesKey)) { [weak self] in
            self?.refresh()
        }
    }

    func status(_ permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    func refresh() {
        var next: [Permission: PermissionStatus] = [:]
        for permission in Permission.allCases { next[permission] = Self.probe(permission, defaults: defaults) }
        if next != statuses { statuses = next }
    }

    /// Asks for a permission. Some show a system prompt; the others (and any
    /// that were already declined) open the right System Settings pane.
    func request(_ permission: Permission) async {
        guard status(permission) != .granted else { return }
        let alreadyDenied = status(permission) == .denied
        switch permission {
        case .accessibility:
            if alreadyDenied { openSystemSettings(for: permission) } else {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        case .inputMonitoring:
            if alreadyDenied || !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { openSystemSettings(for: permission) }
        case .screenRecording:
            if alreadyDenied || !CGRequestScreenCaptureAccess() { openSystemSettings(for: permission) }
        case .calendars:
            if alreadyDenied { openSystemSettings(for: permission) } else { _ = try? await EKEventStore().requestFullAccessToEvents() }
        case .reminders:
            if alreadyDenied { openSystemSettings(for: permission) } else { _ = try? await EKEventStore().requestFullAccessToReminders() }
        case .bluetooth:
            if alreadyDenied { openSystemSettings(for: permission) } else {
                bluetoothRequester = BluetoothRequester { [weak self] in self?.refresh() }
            }
        case .location:
            if alreadyDenied { openSystemSettings(for: permission) } else {
                let manager = CLLocationManager()
                locationManager = manager
                manager.requestWhenInUseAuthorization()
            }
        case .automation:
            openSystemSettings(for: permission)
        case .downloadsFolder:
            if alreadyDenied { openSystemSettings(for: permission) } else { await readDownloadsFolder() }
        }
        refresh()
    }

    /// Reads ~/Downloads off the main thread, which is what shows the
    /// system prompt, and records the answer (see `DownloadsAccess`).
    private func readDownloadsFolder() async {
        if let result = await Task.detached(operation: { DownloadsAccess.read() }).value {
            DownloadsAccess.record(result, defaults: defaults)
        }
        refresh()
    }

    /// The answer can change in System Settings, so once Notched has asked it
    /// reads again when the app is activated. A read that already has an
    /// answer doesn't prompt, and it runs off the main thread regardless.
    private func recheckDownloadsFolder() {
        guard status(.downloadsFolder) != .notDetermined else { return }
        Task { await readDownloadsFolder() }
    }

    func openSystemSettings(for permission: Permission) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(permission.settingsAnchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Probes (read status without prompting)

    private static func probe(_ permission: Permission, defaults: UserDefaults) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .off
        case .inputMonitoring:
            return hidStatus(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .off
        case .automation:
            return .perApp
        case .calendars:
            return eventKitStatus(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return eventKitStatus(EKEventStore.authorizationStatus(for: .reminder))
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        case .location:
            switch CLLocationManager().authorizationStatus {
            case .authorizedAlways: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        case .downloadsFolder:
            // Never reads the folder: that could block on a system prompt.
            return DownloadsAccess.status(defaults: defaults)
        }
    }

    private static func hidStatus(_ access: IOHIDAccessType) -> PermissionStatus {
        switch access {
        case kIOHIDAccessTypeGranted: .granted
        default: .off
        }
    }

    private static func eventKitStatus(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

extension Permission {
    /// The anchor of this permission's pane in System Settings > Privacy & Security.
    var settingsAnchor: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .screenRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        case .calendars: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .bluetooth: "Privacy_Bluetooth"
        case .location: "Privacy_LocationServices"
        case .downloadsFolder: "Privacy_FilesAndFolders"
        }
    }
}

/// Creating a central manager is what makes macOS ask for Bluetooth.
private final class BluetoothRequester: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private let onUpdate: @MainActor () -> Void

    init(onUpdate: @escaping @MainActor () -> Void) {
        self.onUpdate = onUpdate
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let onUpdate = self.onUpdate
        MainActor.assumeIsolated { onUpdate() }
    }
}
