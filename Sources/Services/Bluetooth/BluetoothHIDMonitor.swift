// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit
import IOKit.hid

/// Bluetooth keyboards, mice, trackpads and game controllers, from I/O
/// Registry matching notifications (#27). It only reads the registry and
/// never opens a device, so it needs no permission: not Bluetooth, not
/// Input Monitoring. Exists only while Bluetooth runs.
@MainActor
final class BluetoothHIDMonitor {
    /// The whole list of connected devices, after every change.
    var onChange: ([BluetoothDevice]) -> Void = { _ in }

    private struct Entry {
        let address: String?
        let name: String
        let kind: BluetoothDevice.Kind
    }

    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    /// By registry entry id: one device often has several HID interfaces.
    private var entries: [UInt64: Entry] = [:]
    private let log = Log.module("bluetooth")

    /// True while the registry notifications are installed (tests check `stop()` removes them).
    var isRunning: Bool { port != nil }

    static let transports = [kIOHIDTransportBluetoothValue, kIOHIDTransportBluetoothLowEnergyValue]

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for transport in Self.transports {
            for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
                matching[kIOHIDTransportKey] = transport
                var iterator: io_iterator_t = 0
                let isAdd = type == kIOFirstMatchNotification
                let callback: IOServiceMatchingCallback = isAdd
                    ? { context, iterator in BluetoothHIDMonitor.dispatch(context, iterator, added: true) }
                    : { context, iterator in BluetoothHIDMonitor.dispatch(context, iterator, added: false) }
                let status = IOServiceAddMatchingNotification(port, type, matching, callback, context, &iterator)
                guard status == KERN_SUCCESS else {
                    log.error("Couldn't watch Bluetooth input devices: \(status)")
                    continue
                }
                iterators.append(iterator)
                // Arms the notification, and lists what's already connected.
                drain(iterator, added: isAdd, publish: false)
            }
        }
        publish()
    }

    func stop() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
        entries.removeAll()
    }

    private nonisolated static func dispatch(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t, added: Bool) {
        // The port delivers on the main queue. The pointer crosses as its
        // bit pattern, which is Sendable; it's turned back on the main actor.
        guard let address = context.map({ UInt(bitPattern: $0) }) else { return }
        MainActor.assumeIsolated {
            guard let context = UnsafeMutableRawPointer(bitPattern: address) else { return }
            Unmanaged<BluetoothHIDMonitor>.fromOpaque(context).takeUnretainedValue().drain(iterator, added: added, publish: true)
        }
    }

    private func drain(_ iterator: io_iterator_t, added: Bool, publish shouldPublish: Bool) {
        var changed = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            if added {
                guard let entry = Self.entry(for: service) else { continue }
                entries[id] = entry
                #if DEBUG
                log.debug("Accessory added: \(entry.name, privacy: .public) (\(String(describing: entry.kind), privacy: .public)), address \(entry.address == nil ? "unknown" : "known", privacy: .public)")
                #endif
            } else {
                #if DEBUG
                log.debug("Accessory removed: \(self.entries[id]?.name ?? "unknown", privacy: .public)")
                #endif
                entries[id] = nil
            }
            changed = true
        }
        if changed && shouldPublish { publish() }
    }

    private func publish() {
        onChange(Self.devices(from: Array(entries.values)))
    }

    /// One device per address (or name), with the most specific kind among
    /// its interfaces: a keyboard's media-key interface alone would say "other".
    private static func devices(from entries: [Entry]) -> [BluetoothDevice] {
        var best: [String: BluetoothDevice] = [:]
        for entry in entries {
            let device = BluetoothDevice(address: entry.address, name: entry.name, kind: entry.kind)
            if let existing = best[device.key], rank(existing.kind) >= rank(device.kind) { continue }
            best[device.key] = device
        }
        return best.values.sorted { $0.key < $1.key }
    }

    private static func rank(_ kind: BluetoothDevice.Kind) -> Int {
        switch kind {
        case .other: 0
        case .gameController, .mouse, .keyboard: 1
        case .trackpad: 2
        case .audio: 3
        }
    }

    private static func entry(for service: io_service_t) -> Entry? {
        func property<T>(_ key: String) -> T? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
        }
        guard let name: String = property(kIOHIDProductKey), !name.isEmpty else { return nil }
        let kind = BluetoothDevice.Kind.hid(
            usagePage: property(kIOHIDPrimaryUsagePageKey) ?? 0,
            usage: property(kIOHIDPrimaryUsageKey) ?? 0,
            name: name,
            vendorID: property(kIOHIDVendorIDKey)
        )
        return Entry(address: property("DeviceAddress"), name: name, kind: kind)
    }
}
