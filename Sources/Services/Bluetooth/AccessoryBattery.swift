// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A connected Bluetooth device's battery, as macOS's own Bluetooth report
/// gives it (#28, ADR-0030). Original code; AirBattery was never read for it.
struct AccessoryBattery: Equatable, Sendable {
    /// The device's name as macOS lists it ("Charlie's AirPods Pro").
    let name: String
    /// Its Bluetooth address, normalised like `BluetoothDevice.key`, used only
    /// to match the device and never stored or logged.
    let address: String?
    /// One battery (headphones, speakers, mice, keyboards).
    let main: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?

    /// The one number a banner shows: the single battery, or the lower bud
    /// (the one that runs out first). Nil when the device reports nothing.
    var headline: Int? {
        if let main { return main }
        switch (left, right) {
        case let (left?, right?): return min(left, right)
        case let (left?, nil): return left
        case let (nil, right?): return right
        default: return nil
        }
    }

    /// Whether this entry describes `device`: by address when both have one,
    /// otherwise by name without the owner's "Charlie's ".
    func matches(_ device: BluetoothDevice) -> Bool {
        if let address, device.key.hasPrefix("bt:") { return device.key == "bt:\(address)" }
        return Self.comparableName(name) == Self.comparableName(device.name)
    }

    static func comparableName(_ name: String) -> String {
        BluetoothDevice.displayName(name).lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }
}

/// Parses `system_profiler SPBluetoothDataType -json`. Pure.
///
/// Reads only the connected devices and only the battery fields
/// (`device_batteryLevelMain/Left/Right/Case`, strings like "52%") and the
/// address. A missing field means unknown, never 0 %. Serial numbers are
/// never read.
enum AccessoryBatteryParser {
    static func parse(_ json: Data) -> [AccessoryBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [AccessoryBattery] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any] else { continue }
                    let battery = AccessoryBattery(
                        name: name,
                        address: (properties["device_address"] as? String).flatMap(BluetoothDevice.normalizedAddress(in:)),
                        main: percent(properties["device_batteryLevelMain"]),
                        left: percent(properties["device_batteryLevelLeft"]),
                        right: percent(properties["device_batteryLevelRight"]),
                        caseLevel: percent(properties["device_batteryLevelCase"])
                    )
                    if battery.headline != nil || battery.caseLevel != nil { result.append(battery) }
                }
            }
        }
        return result
    }

    /// "52%" (or 52) → 52, clamped to 0…100; anything else → nil.
    static func percent(_ value: Any?) -> Int? {
        let number: Int?
        switch value {
        case let text as String: number = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ").union(.whitespaces)))
        case let int as Int: number = int
        default: number = nil
        }
        return number.map { min(max($0, 0), 100) }
    }

    /// The battery entry for `device`, if the report has one.
    static func battery(for device: BluetoothDevice, in report: [AccessoryBattery]) -> AccessoryBattery? {
        report.first { $0.matches(device) }
    }
}

/// Runs `system_profiler` once, off the main thread, and gives up after
/// `timeout`. Called once when a device connects, never on a timer (ADR-0030).
enum AccessoryBatteryReader {
    static let timeout: TimeInterval = 3

    static func read() async -> [AccessoryBattery] {
        await Task.detached(priority: .utility) { runBlocking() }.value
    }

    private final class Job: @unchecked Sendable {
        let process = Process()
    }

    private static func runBlocking() -> [AccessoryBattery] {
        let job = Job()
        job.process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        job.process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        job.process.standardOutput = pipe
        job.process.standardError = FileHandle.nullDevice
        do { try job.process.run() } catch { return [] }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            if job.process.isRunning { job.process.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        job.process.waitUntilExit()
        guard job.process.terminationStatus == 0 else { return [] }
        return AccessoryBatteryParser.parse(data)
    }
}
