// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import ObjectiveC

/// A private-API wrapper for the battery levels IOBluetooth keeps on paired
/// devices (AirPods: left, right, case). `IOBluetoothDevice` is public; its
/// battery properties are not, so they're read by key only after checking
/// that the device answers to them, never assumed. Original code (#28).
///
/// If the framework, the class or the properties are missing, `isAvailable`
/// is false or the values are empty, the failure is logged once, and the
/// feature hides itself. Main-actor only, like IOBluetooth itself.
@MainActor
enum IOBluetoothBattery {
    /// One paired device, as plain values. No Bluetooth address.
    struct Reading: Sendable {
        var name: String
        var isConnected: Bool
        /// Property name → percent, for whichever battery properties answered.
        var levels: [String: Int]
    }

    /// The properties tried, in order of usefulness.
    static let batteryKeys = [
        "batteryPercentLeft", "batteryPercentRight", "batteryPercentCase",
        "batteryPercentSingle", "batteryPercentCombined",
    ]

    private static let deviceClass: NSObject.Type? = {
        guard dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY) != nil,
              let type = NSClassFromString("IOBluetoothDevice") as? NSObject.Type else {
            Log.privateAPI.error("IOBluetoothDevice is unavailable; accessory battery levels are hidden")
            return nil
        }
        return type
    }()

    static var isAvailable: Bool { deviceClass != nil }

    /// Every paired device, or nil when IOBluetooth isn't available.
    static func pairedDevices() -> [Reading]? {
        guard let deviceClass else { return nil }
        let classObject: AnyObject = deviceClass
        let selector = NSSelectorFromString("pairedDevices")
        guard classObject.responds(to: selector),
              let devices = classObject.perform(selector)?.takeUnretainedValue() as? [NSObject] else { return [] }
        return devices.map { device in
            var levels: [String: Int] = [:]
            for key in batteryKeys where device.responds(to: NSSelectorFromString(key)) {
                if let number = device.value(forKey: key) as? NSNumber { levels[key] = number.intValue }
            }
            let name = device.responds(to: NSSelectorFromString("name")) ? device.value(forKey: "name") as? String : nil
            let connected = device.responds(to: NSSelectorFromString("isConnected")) ? device.value(forKey: "connected") as? Bool : nil
            return Reading(name: name ?? "?", isConnected: connected ?? false, levels: levels)
        }
    }

    /// For the spike: every method of `IOBluetoothDevice` whose name mentions a
    /// battery, to see what this macOS offers.
    static func batteryMethodNames() -> [String] {
        guard let deviceClass else { return [] }
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(deviceClass, &count) else { return [] }
        defer { free(methods) }
        return (0..<Int(count))
            .map { NSStringFromSelector(method_getName(methods[$0])) }
            .filter { $0.localizedCaseInsensitiveContains("battery") }
            .sorted()
    }
}
