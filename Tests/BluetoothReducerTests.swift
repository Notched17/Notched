// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Connect and disconnect banners for every Bluetooth device (#27).
@Suite("BluetoothReducer")
struct BluetoothReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 60_000)

    let airPods = BluetoothDevice(address: "AA-BB-CC-DD-EE-01", name: "Charlie's AirPods Pro", kind: .audio(symbol: "airpods.pro"))
    /// The same AirPods as the input side (HID) sees them.
    let airPodsHID = BluetoothDevice(address: "aa:bb:cc:dd:ee:01", name: "AirPods Pro", kind: .other)
    let keyboard = BluetoothDevice(address: "aa-bb-cc-dd-ee-02", name: "Magic Keyboard", kind: .keyboard)
    let mouse = BluetoothDevice(address: "aa-bb-cc-dd-ee-03", name: "Magic Mouse", kind: .mouse(isApple: true))

    /// A reducer that has seen both sources' starting lists.
    private func seeded(audio: [BluetoothDevice] = [], input: [BluetoothDevice] = []) -> BluetoothReducer {
        var sut = BluetoothReducer()
        _ = sut.reduce(.devices(.audio, audio), now: t0 - 100)
        _ = sut.reduce(.devices(.input, input), now: t0 - 100)
        return sut
    }

    @Test("Devices already connected at start are silent")
    func baselineIsSilent() {
        var sut = BluetoothReducer()
        #expect(sut.reduce(.devices(.audio, [airPods]), now: t0).isEmpty)
        #expect(sut.reduce(.devices(.input, [keyboard]), now: t0).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 5).isEmpty)
    }

    @Test("A new device is announced once it has been connected a second")
    func connectAfterSettle() {
        var sut = seeded()
        #expect(sut.reduce(.devices(.audio, [airPods]), now: t0) == [.wake(t0 + 1)])
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.connected(airPods))])
        #expect(sut.reduce(.devices(.audio, [airPods]), now: t0 + 2).isEmpty)
    }

    @Test("A keyboard, mouse or trackpad is announced too")
    func inputDevicesAnnounced() {
        var sut = seeded()
        _ = sut.reduce(.devices(.input, [keyboard]), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.connected(keyboard))])
    }

    @Test("A device that appears for less than a second says nothing")
    func connectBlipIsSilent() {
        var sut = seeded()
        _ = sut.reduce(.devices(.audio, [airPods]), now: t0)
        #expect(sut.reduce(.devices(.audio, []), now: t0 + 0.5).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 1).isEmpty)
    }

    @Test("The audio and input views of one device make one banner, with the audio symbol")
    func audioAndInputViewsMerge() {
        var sut = seeded()
        _ = sut.reduce(.devices(.input, [airPodsHID]), now: t0)
        _ = sut.reduce(.devices(.audio, [airPods]), now: t0 + 0.3)
        let effects = sut.reduce(.tick, now: t0 + 1)
        #expect(effects == [.banner(.connected(airPods))])
        if case .banner(.connected(let device)) = effects.first { #expect(device.symbol == "airpods.pro") }
    }

    @Test("A disconnect is announced once every view of the device has been gone two seconds")
    func disconnectAfterLastSourceLeaves() {
        var sut = seeded(audio: [airPods], input: [airPodsHID])
        #expect(sut.reduce(.devices(.audio, []), now: t0).isEmpty)
        #expect(sut.reduce(.devices(.input, []), now: t0 + 1) == [.wake(t0 + 3)])
        #expect(sut.reduce(.tick, now: t0 + 3) == [.banner(.disconnected(airPods))])
        #expect(sut.reduce(.tick, now: t0 + 10).isEmpty)
    }

    @Test("A device that drops and comes back within two seconds says nothing")
    func reconnectBlipIsSilent() {
        var sut = seeded(audio: [airPods])
        #expect(sut.reduce(.devices(.audio, []), now: t0) == [.wake(t0 + 2)])
        #expect(sut.reduce(.devices(.audio, [airPods]), now: t0 + 1).isEmpty)
        #expect(sut.reduce(.tick, now: t0 + 2).isEmpty)
    }

    @Test("Two devices connecting together each get a banner")
    func twoDevicesAtOnce() {
        var sut = seeded()
        _ = sut.reduce(.devices(.input, [mouse, keyboard]), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.connected(keyboard)), .banner(.connected(mouse))])
    }

    @Test("Connect then disconnect then connect again, each announced")
    func fullCycle() {
        var sut = seeded()
        _ = sut.reduce(.devices(.input, [mouse]), now: t0)
        #expect(sut.reduce(.tick, now: t0 + 1) == [.banner(.connected(mouse))])
        _ = sut.reduce(.devices(.input, []), now: t0 + 10)
        #expect(sut.reduce(.tick, now: t0 + 12) == [.banner(.disconnected(mouse))])
        _ = sut.reduce(.devices(.input, [mouse]), now: t0 + 20)
        #expect(sut.reduce(.tick, now: t0 + 21) == [.banner(.connected(mouse))])
    }

    // MARK: Identity and symbols

    @Test("Addresses are found in CoreAudio UIDs and HID properties, and normalised")
    func addressNormalisation() {
        #expect(BluetoothDevice.normalizedAddress(in: "AA-BB-CC-DD-EE-FF:output") == "aa-bb-cc-dd-ee-ff")
        #expect(BluetoothDevice.normalizedAddress(in: "aa:bb:cc:dd:ee:ff") == "aa-bb-cc-dd-ee-ff")
        #expect(BluetoothDevice.normalizedAddress(in: "BuiltInSpeakerDevice") == nil)
        #expect(BluetoothDevice.normalizedAddress(in: "AA-BB-CC") == nil)
        #expect(BluetoothDevice.key(address: "AA:BB:CC:DD:EE:FF", name: "x") == "bt:aa-bb-cc-dd-ee-ff")
        #expect(BluetoothDevice.key(address: nil, name: "  Magic  Keyboard ") == "name:magic keyboard")
        #expect(airPods.key == airPodsHID.key)
    }

    @Test("Each kind of device has its own symbol")
    func symbols() {
        #expect(airPods.symbol == "airpods.pro")
        #expect(keyboard.symbol == "keyboard")
        #expect(mouse.symbol == "magicmouse")
        #expect(BluetoothDevice(address: nil, name: "MX Master", kind: .mouse(isApple: false)).symbol == "computermouse")
        #expect(BluetoothDevice(address: nil, name: "Magic Trackpad", kind: .trackpad).symbol == "rectangle.and.hand.point.up.left")
        #expect(BluetoothDevice(address: nil, name: "DualSense", kind: .gameController).symbol == "gamecontroller")
        #expect(BluetoothDevice(address: nil, name: "Gadget", kind: .other).symbol == "dot.radiowaves.left.and.right")
    }

    @Test("HID usage tells keyboards, mice, trackpads and controllers apart")
    func hidKinds() {
        typealias Kind = BluetoothDevice.Kind
        #expect(Kind.hid(usagePage: 1, usage: 6, name: "Keychron K2", vendorID: 0x05AC) == .keyboard)
        #expect(Kind.hid(usagePage: 1, usage: 2, name: "Magic Mouse", vendorID: 0x004C) == .mouse(isApple: true))
        #expect(Kind.hid(usagePage: 1, usage: 2, name: "MX Master 3", vendorID: 0x046D) == .mouse(isApple: false))
        #expect(Kind.hid(usagePage: 1, usage: 2, name: "Magic Trackpad", vendorID: 0x004C) == .trackpad)
        #expect(Kind.hid(usagePage: 0x0D, usage: 5, name: "Touchpad", vendorID: nil) == .trackpad)
        #expect(Kind.hid(usagePage: 1, usage: 5, name: "Xbox Wireless Controller", vendorID: 0x045E) == .gameController)
        #expect(Kind.hid(usagePage: 0x0C, usage: 1, name: "AirPods Pro", vendorID: 0x004C) == .other)
    }
}
