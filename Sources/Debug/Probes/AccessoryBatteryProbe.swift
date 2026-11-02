// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import CoreBluetooth
import Foundation

/// M6 spike 6.2 (#28): can Notched read AirPods' left, right and case battery
/// reliably? Three routes, all original code (never AirBattery):
///
/// - **A** IOBluetooth's private battery properties (`IOBluetoothBattery`).
/// - **B** Apple's proximity-pairing Bluetooth LE advertisements, decoded
///   from the publicly documented layout (`ProximityPairing`), scanned for a
///   few seconds only.
/// - **C** `system_profiler SPBluetoothDataType -json`, Apple's own report.
///
/// Each route logs what it returns and how long it took, plus the Bluetooth
/// permission before and after.
///
///     open -g "notched://debug/probe?name=battery-accessory&action=run"        (A, B for 10 s, C)
///     open -g "notched://debug/probe?name=battery-accessory&action=b&seconds=20"
///
/// Results: `~/Library/Logs/Notched/spike-battery-accessory.txt`. Bluetooth
/// addresses are never written.
@MainActor
enum AccessoryBatteryProbe {
    private static var report: ProbeReport?
    private static var scanner: ProximityScanner?

    static func handle(action: String, seconds: Double?) {
        let report = Self.report ?? ProbeReport(name: "battery-accessory")
        Self.report = report
        let duration = min(max(seconds ?? 10, 2), 60)
        report.line("--- \(action): Bluetooth permission \(authorization())")
        switch action {
        case "a": routeA(report)
        case "b": routeB(report, seconds: duration)
        case "c": routeC(report)
        case "run":
            routeA(report)
            routeC(report)
            routeB(report, seconds: duration)
        default: report.line("unknown action \(action)")
        }
    }

    private static func authorization() -> String {
        switch CBManager.authorization {
        case .allowedAlways: "allowed"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not asked yet"
        @unknown default: "unknown"
        }
    }

    // MARK: A. IOBluetooth

    private static func routeA(_ report: ProbeReport) {
        let started = Date()
        guard IOBluetoothBattery.isAvailable else { report.line("A: IOBluetooth unavailable"); return }
        report.line("A: IOBluetoothDevice battery methods on this macOS: \(IOBluetoothBattery.batteryMethodNames().joined(separator: ", "))")
        guard let devices = IOBluetoothBattery.pairedDevices() else { report.line("A: no answer"); return }
        let elapsed = Date().timeIntervalSince(started)
        report.line("A: \(devices.count) paired device(s) in \(milliseconds(elapsed)); permission now \(authorization())")
        for device in devices {
            let levels = device.levels.isEmpty ? "no battery values" : device.levels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)%" }.joined(separator: " ")
            report.line("A:   \"\(device.name)\" connected=\(device.isConnected) \(levels)")
        }
    }

    // MARK: B. BLE proximity-pairing advertisements

    private static func routeB(_ report: ProbeReport, seconds: Double) {
        guard Self.scanner == nil else { report.line("B: already scanning"); return }
        report.line("B: scanning for \(Int(seconds)) s")
        let scanner = ProximityScanner(report: report)
        Self.scanner = scanner
        scanner.start()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            scanner.stop()
            Self.scanner = nil
            report.line("B: done; permission now \(authorization())")
        }
    }

    // MARK: C. system_profiler

    private static func routeC(_ report: ProbeReport) {
        let started = Date()
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) { SystemProfilerBluetooth.run() }.value
            let elapsed = Date().timeIntervalSince(started)
            switch result {
            case .failure(let message): report.line("C: failed after \(milliseconds(elapsed)): \(message)")
            case .success(let devices):
                report.line("C: \(devices.count) connected device(s) in \(milliseconds(elapsed)); permission now \(authorization())")
                for device in devices { report.line("C:   \(device)") }
            }
        }
    }

    static func milliseconds(_ interval: TimeInterval) -> String { "\(Int((interval * 1000).rounded())) ms" }
}

// MARK: Route B

/// Scans for Apple's proximity-pairing advertisements and logs each distinct
/// reading once per device (so a 10 s scan doesn't log hundreds of lines).
/// Main-actor isolated; the delegate callbacks arrive on the main queue and
/// pass only plain values across.
@MainActor
final class ProximityScanner: NSObject, CBCentralManagerDelegate {
    private let report: ProbeReport
    private var manager: CBCentralManager?
    private let started = Date()
    private var seen: [String: String] = [:]
    private var appleAdverts = 0
    private var otherTypes: [UInt8: Int] = [:]

    init(report: ProbeReport) {
        self.report = report
        super.init()
    }

    func start() {
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        manager?.stopScan()
        manager = nil
        let types = otherTypes.sorted { $0.key < $1.key }.map { String(format: "0x%02X×%d", $0.key, $0.value) }.joined(separator: " ")
        report.line("B: \(appleAdverts) Apple adverts seen; other Apple message types: \(types.isEmpty ? "none" : types)")
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            report.line("B: Bluetooth state \(state.rawValue) (5 = on)")
            guard state == .poweredOn else { return }
            manager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let identifier = String(peripheral.identifier.uuidString.prefix(8))
        let rssi = RSSI.intValue
        MainActor.assumeIsolated { handle(data, identifier: identifier, rssi: rssi) }
    }

    private func handle(_ data: Data, identifier: String, rssi: Int) {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == 0x4C, bytes[1] == 0x00 else { return }
        appleAdverts += 1
        guard let reading = ProximityPairing.decode(bytes) else {
            otherTypes[bytes[2], default: 0] += 1
            return
        }
        let summary = reading.summary
        guard seen[identifier] != summary else { return }
        seen[identifier] = summary
        let elapsed = AccessoryBatteryProbe.milliseconds(Date().timeIntervalSince(started))
        report.line("B: [\(identifier)] rssi \(rssi) after \(elapsed): \(summary)")
        report.line("B:   raw \(bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " "))…")
    }
}

/// Apple's proximity-pairing message (type 0x07) in manufacturer data, decoded
/// from the publicly documented layout (Celosia & Cunche, "Discontinued
/// Privacy", PETS 2020, and furiousMAC's continuity notes). After the company id
/// 4C 00: type, length, prefix, model (2 bytes), status, battery nibbles,
/// charging flags + case nibble, lid counter, colour, then an encrypted part.
/// A nibble of 0–10 is tens of percent; 15 means unknown.
enum ProximityPairing {
    struct Reading: Equatable {
        var model: String
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        var leftCharging: Bool
        var rightCharging: Bool
        var caseCharging: Bool
        var flipped: Bool

        var summary: String {
            func level(_ value: Int?) -> String { value.map { "\($0)%" } ?? "-" }
            return "model \(model) (\(Self.modelName(model))) L \(level(left))\(leftCharging ? "⚡" : "") R \(level(right))\(rightCharging ? "⚡" : "") case \(level(caseLevel))\(caseCharging ? "⚡" : "") flipped=\(flipped)"
        }

        static func modelName(_ model: String) -> String {
            switch model {
            case "0220": "AirPods (1st gen)"
            case "0F20": "AirPods (2nd gen)"
            case "1320": "AirPods (3rd gen)"
            case "1920", "1B20": "AirPods 4"
            case "0E20": "AirPods Pro"
            case "1420", "2420": "AirPods Pro 2"
            case "0A20", "1F20": "AirPods Max"
            default: "unknown model"
            }
        }
    }

    /// `bytes` is the whole manufacturer data, starting with 4C 00.
    static func decode(_ bytes: [UInt8]) -> Reading? {
        guard bytes.count >= 12, bytes[0] == 0x4C, bytes[1] == 0x00, bytes[2] == 0x07 else { return nil }
        let payload = Array(bytes[2...])   // payload[0] is the type
        let model = String(format: "%02X%02X", payload[3], payload[4])
        let status = payload[5]
        // Which bud's level comes first depends on which one is "primary".
        let flipped = (status >> 4) & 0x02 == 0
        let high = Int(payload[6] >> 4), low = Int(payload[6] & 0x0F)
        let charging = Int(payload[7] >> 4), caseNibble = Int(payload[7] & 0x0F)
        func percent(_ nibble: Int) -> Int? { nibble <= 10 ? nibble * 10 : nil }
        return Reading(
            model: model,
            left: percent(flipped ? high : low),
            right: percent(flipped ? low : high),
            caseLevel: percent(caseNibble),
            leftCharging: charging & (flipped ? 0b0010 : 0b0001) != 0,
            rightCharging: charging & (flipped ? 0b0001 : 0b0010) != 0,
            caseCharging: charging & 0b0100 != 0,
            flipped: flipped
        )
    }
}

// MARK: Route C

enum SystemProfilerBluetooth {
    enum Result: Sendable {
        case success([String])
        case failure(String)
    }

    /// Runs `system_profiler SPBluetoothDataType -json` and returns one line per
    /// connected device: its name, product id, kind and every battery field.
    static func run() -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure("couldn't start: \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .failure("exit status \(process.terminationStatus)") }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return .failure("unexpected JSON") }
        var lines: [String] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any] else { continue }
                    // Every battery field, plus what kind of device it is. Never the address.
                    let fields = properties
                        .filter { $0.key.localizedCaseInsensitiveContains("battery") || ["device_productID", "device_minorType", "device_vendorID"].contains($0.key) }
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }
                    lines.append("\"\(name)\" " + (fields.isEmpty ? "(no battery fields)" : fields.joined(separator: " ")))
                }
            }
        }
        return .success(lines)
    }
}
#endif
