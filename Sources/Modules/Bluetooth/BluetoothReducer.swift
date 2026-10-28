// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A connected Bluetooth device, as one of the module's sources sees it
/// (#27): CoreAudio for audio devices, the I/O Registry's HID devices for
/// keyboards, mice, trackpads and controllers.
struct BluetoothDevice: Equatable, Sendable {
    /// Where a device was seen. One device can show up in both (AirPods have
    /// an audio output and a small HID interface).
    enum Source: Hashable, Sendable {
        case audio
        case input
    }

    enum Kind: Equatable, Sendable {
        /// An audio output, with M2's symbol for it (AirPods, Beats, headphones…).
        case audio(symbol: String)
        case keyboard
        case mouse(isApple: Bool)
        case trackpad
        case gameController
        case other

        /// Classifies a HID device from its primary usage (HID Usage Tables:
        /// page 1 Generic Desktop, page 0x0D Digitizer) and name.
        static func hid(usagePage: Int, usage: Int, name: String, vendorID: Int?) -> Kind {
            let lowered = name.lowercased()
            if lowered.contains("trackpad") || usagePage == 0x0D { return .trackpad }
            guard usagePage == 1 else { return .other }
            switch usage {
            case 6, 7: return .keyboard
            case 1, 2: return .mouse(isApple: vendorID.map(appleVendorIDs.contains) ?? false)
            case 4, 5, 8: return .gameController
            default: return .other
            }
        }

        /// Apple's USB vendor id and its Bluetooth SIG company id.
        private static let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]
    }

    /// Identifies the device across sources: its Bluetooth address when known.
    let key: String
    let name: String
    let kind: Kind

    init(address: String?, name: String, kind: Kind) {
        key = Self.key(address: address, name: name)
        self.name = name
        self.kind = kind
    }

    var isAudio: Bool {
        if case .audio = kind { true } else { false }
    }

    /// The SF Symbol for the banner.
    var symbol: String {
        switch kind {
        case .audio(let symbol): symbol
        case .keyboard: "keyboard"
        case .mouse(let isApple): isApple ? "magicmouse" : "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .gameController: "gamecontroller"
        case .other: "dot.radiowaves.left.and.right"
        }
    }

    /// The name for a banner: "Charlie's AirPods Pro" becomes "AirPods Pro",
    /// since the owner is always the person at this Mac.
    static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for apostrophe in ["'s ", "\u{2019}s "] {
            guard let range = trimmed.range(of: apostrophe) else { continue }
            let rest = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if let first = rest.first, first.isUppercase || first.isNumber { return rest }
        }
        return trimmed
    }

    static func key(address: String?, name: String) -> String {
        if let address = address.flatMap(normalizedAddress(in:)) { return "bt:\(address)" }
        let words = name.lowercased().split(whereSeparator: \.isWhitespace)
        return "name:\(words.joined(separator: " "))"
    }

    /// The first Bluetooth address (six hex pairs joined by `-` or `:`) in
    /// `text`, lowercased and joined by `-`. CoreAudio puts it in a
    /// Bluetooth device's UID ("AA-BB-CC-DD-EE-FF:output"); HID devices have
    /// it as `DeviceAddress`.
    static func normalizedAddress(in text: String) -> String? {
        let characters = Array(text.lowercased())
        guard characters.count >= 17 else { return nil }
        for start in 0...(characters.count - 17) {
            var pairs: [String] = []
            var index = start
            while pairs.count < 6 {
                let pair = characters[index..<index + 2]
                guard pair.allSatisfy(\.isHexDigit) else { break }
                pairs.append(String(pair))
                index += 2
                if pairs.count < 6 {
                    guard characters[index] == "-" || characters[index] == ":" else { break }
                    index += 1
                }
            }
            if pairs.count == 6 { return pairs.joined(separator: "-") }
        }
        return nil
    }
}

/// Connect and disconnect banners for every Bluetooth device (#27). Pure.
///
/// - Each source reports its whole current list. A source's first list is
///   the starting state and is silent.
/// - A device is connected while any source reports it. Its audio view
///   wins for the name and symbol.
/// - Connect is announced once the device has been there 1 s (CoreAudio
///   and HID see it at slightly different moments; a flicker says nothing).
/// - Disconnect is announced once every view has been gone 2 s, so a
///   reconnect blip (AirPods switching codec) says nothing.
struct BluetoothReducer: Sendable {
    static let connectSettle: TimeInterval = 1
    static let disconnectSettle: TimeInterval = 2

    enum Event: Equatable, Sendable {
        case devices(BluetoothDevice.Source, [BluetoothDevice])
        /// The wake the reducer asked for.
        case tick
    }

    enum Banner: Equatable, Sendable {
        case connected(BluetoothDevice)
        case disconnected(BluetoothDevice)
    }

    enum Effect: Equatable, Sendable {
        case banner(Banner)
        case wake(Date)
    }

    private var reported: [BluetoothDevice.Source: [String: BluetoothDevice]] = [:]
    /// Connected, as far as the user has been told.
    private var announced: [String: BluetoothDevice] = [:]
    private var pendingConnect: [String: Date] = [:]
    private var pendingDisconnect: [String: Date] = [:]

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        if case .devices(let source, let devices) = event {
            let isFirst = reported[source] == nil
            reported[source] = Dictionary(devices.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            if isFirst {
                for device in devices where pendingConnect[device.key] == nil {
                    announced[device.key] = merged(device.key)
                }
            }
        }
        return update(now: now)
    }

    private mutating func update(now: Date) -> [Effect] {
        let present = Set(reported.values.flatMap(\.keys))
        for key in present {
            if let known = announced[key] {
                // Keep the audio view once known, so a disconnect still says
                // "AirPods Pro" after the audio side leaves first.
                if let current = merged(key), current.isAudio || !known.isAudio { announced[key] = current }
                pendingDisconnect[key] = nil
            } else if pendingConnect[key] == nil {
                pendingConnect[key] = now
            }
        }
        for key in pendingConnect.keys where !present.contains(key) { pendingConnect[key] = nil }
        for key in announced.keys where !present.contains(key) && pendingDisconnect[key] == nil {
            pendingDisconnect[key] = now
        }

        var effects: [Effect] = []
        for key in pendingConnect.keys.sorted() where now >= pendingConnect[key]!.addingTimeInterval(Self.connectSettle) {
            pendingConnect[key] = nil
            guard let device = merged(key) else { continue }
            announced[key] = device
            effects.append(.banner(.connected(device)))
        }
        for key in pendingDisconnect.keys.sorted() where now >= pendingDisconnect[key]!.addingTimeInterval(Self.disconnectSettle) {
            pendingDisconnect[key] = nil
            if let device = announced.removeValue(forKey: key) { effects.append(.banner(.disconnected(device))) }
        }
        let deadlines = pendingConnect.values.map { $0.addingTimeInterval(Self.connectSettle) }
            + pendingDisconnect.values.map { $0.addingTimeInterval(Self.disconnectSettle) }
        if let next = deadlines.min() { effects.append(.wake(next)) }
        return effects
    }

    /// The device's best description across sources: the audio view if any.
    private func merged(_ key: String) -> BluetoothDevice? {
        reported[.audio]?[key] ?? reported[.input]?[key]
    }
}
