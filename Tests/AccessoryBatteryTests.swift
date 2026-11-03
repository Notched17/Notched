// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// AirPods and accessory battery (#28, ADR-0030): the parser for macOS's own
/// Bluetooth report, and the banner it feeds. The JSON is trimmed from the real
/// output recorded on 3 Nov 2026 (addresses and serials made up).
@Suite("AccessoryBattery")
struct AccessoryBatteryTests {
    static let report = """
    {"SPBluetoothDataType":[{
      "device_connected":[
        {"Charlie\u{2019}s AirPods Pro":{"device_address":"AA:BB:CC:DD:EE:01","device_batteryLevelCase":"52%","device_batteryLevelLeft":"100%","device_batteryLevelRight":"90%","device_minorType":"Headphones","device_productID":"0x2024","device_serialNumber":"SECRET1","device_vendorID":"0x004C"}},
        {"Charlie\u{2019}s AirPods Max":{"device_address":"AA:BB:CC:DD:EE:02","device_batteryLevelMain":"100%","device_serialNumber":"SECRET2"}},
        {"BluetoothMouse3600":{"device_address":"AA:BB:CC:DD:EE:03","device_batteryLevelMain":"41%"}},
        {"Some Speaker":{"device_address":"AA:BB:CC:DD:EE:04","device_minorType":"Speaker"}}
      ],
      "device_not_connected":[
        {"Old Headphones":{"device_address":"AA:BB:CC:DD:EE:05","device_batteryLevelMain":"7%"}}
      ]}]}
    """

    private func parsed() -> [AccessoryBattery] { AccessoryBatteryParser.parse(Data(Self.report.utf8)) }

    @Test("Only connected devices that report a battery are listed")
    func listsConnectedWithBattery() {
        let names = parsed().map(\.name)
        #expect(Set(names) == ["Charlie\u{2019}s AirPods Pro", "Charlie\u{2019}s AirPods Max", "BluetoothMouse3600"])
    }

    @Test("Buds report left, right and case; the headline is the lower bud")
    func budsHeadline() throws {
        let pro = try #require(parsed().first { $0.name.contains("Pro") })
        #expect(pro.left == 100 && pro.right == 90 && pro.caseLevel == 52 && pro.main == nil)
        #expect(pro.headline == 90)
    }

    @Test("One-battery devices report main")
    func mainHeadline() throws {
        let max = try #require(parsed().first { $0.name.contains("Max") })
        #expect(max.main == 100 && max.headline == 100)
    }

    @Test("Percent strings parse and clamp; missing is unknown, not zero")
    func percentParsing() {
        #expect(AccessoryBatteryParser.percent("52%") == 52)
        #expect(AccessoryBatteryParser.percent(" 7 % ") == 7)
        #expect(AccessoryBatteryParser.percent("140%") == 100)
        #expect(AccessoryBatteryParser.percent(30) == 30)
        #expect(AccessoryBatteryParser.percent(nil) == nil)
        #expect(AccessoryBatteryParser.percent("n/a") == nil)
    }

    @Test("One bud alone is its own headline")
    func oneBud() {
        let one = AccessoryBattery(name: "x", address: nil, main: nil, left: 60, right: nil, caseLevel: nil)
        #expect(one.headline == 60)
        #expect(AccessoryBattery(name: "x", address: nil, main: nil, left: nil, right: nil, caseLevel: 80).headline == nil)
    }

    @Test("Garbage, an empty report or the wrong shape gives nothing")
    func badInput() {
        #expect(AccessoryBatteryParser.parse(Data()).isEmpty)
        #expect(AccessoryBatteryParser.parse(Data("{}".utf8)).isEmpty)
        #expect(AccessoryBatteryParser.parse(Data("[1,2]".utf8)).isEmpty)
        #expect(AccessoryBatteryParser.parse(Data("{\"SPBluetoothDataType\":[{}]}".utf8)).isEmpty)
    }

    @Test("A device matches by address, or by name without the owner")
    func matching() throws {
        let report = parsed()
        // CoreAudio gives the address in the UID; the name may differ in apostrophe style.
        let byAddress = BluetoothDevice(address: "AA-BB-CC-DD-EE-01", name: "Anything", kind: .audio(symbol: "airpods.pro"))
        #expect(AccessoryBatteryParser.battery(for: byAddress, in: report)?.headline == 90)
        let byName = BluetoothDevice(address: nil, name: "Charlie's AirPods Max", kind: .audio(symbol: "airpods.max"))
        #expect(AccessoryBatteryParser.battery(for: byName, in: report)?.headline == 100)
        let other = BluetoothDevice(address: "11-22-33-44-55-66", name: "AirPods Pro", kind: .audio(symbol: "airpods.pro"))
        #expect(AccessoryBatteryParser.battery(for: other, in: report) == nil)
    }

    @Test("The report's serial numbers are never read")
    func noSerials() {
        let text = String(describing: parsed())
        #expect(!text.contains("SECRET"))
    }

    @Test("The banner shows the level and a battery; without one it is the plain name")
    @MainActor
    func banners() {
        let device = BluetoothDevice(address: "AA-BB-CC-DD-EE-01", name: "Charlie's AirPods Pro", kind: .audio(symbol: "airpods.pro"))
        let with = BluetoothModule.banner(.connected(device), batteryLevel: 90)
        #expect(with.accessibilityLabel == "Charlie's AirPods Pro connected, battery 90 percent")
        let without = BluetoothModule.banner(.connected(device))
        #expect(without.accessibilityLabel == "Charlie's AirPods Pro connected")
    }

    @Test("Showing the battery is on by default and remembered")
    @MainActor
    func setting() throws {
        let suite = "AccessoryBatteryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = BluetoothSettings(defaults: defaults)
        #expect(settings.showBattery)
        settings.showBattery = false
        #expect(BluetoothSettings(defaults: defaults).showBattery == false)
    }
}
