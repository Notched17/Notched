// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio
import Observation

/// The Mac's audio outputs and the current one, kept up to date by CoreAudio
/// property listeners (no polling), and a way to switch (#16).
///
/// One instance is shared by the modules that need it (`ModuleServices`).
/// Listeners exist only while at least one of them holds it
/// (`acquire()`/`release()`), e.g. while Now Playing or Bluetooth is on.
@MainActor
@Observable
final class AudioOutputService {
    private(set) var devices: [AudioOutputDevice] = []
    private(set) var current: AudioOutputDevice?

    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    @ObservationIgnored private var listeners: [Listener] = []
    @ObservationIgnored private var dataSourceListener: Listener?
    @ObservationIgnored private let log = Log.module("media")
    @ObservationIgnored private var clients = 0

    /// Starts listening for the first holder.
    func acquire() {
        clients += 1
        if clients == 1 { start() }
    }

    /// Stops listening once the last holder lets go.
    func release() {
        guard clients > 0 else { return }
        clients -= 1
        if clients == 0 { stop() }
    }

    private func start() {
        guard listeners.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            if let listener = listen(AudioObjectID(kAudioObjectSystemObject), selector: selector, scope: kAudioObjectPropertyScopeGlobal) {
                listeners.append(listener)
            }
        }
        reload()
    }

    private func stop() {
        for listener in listeners { remove(listener) }
        listeners.removeAll()
        if let dataSourceListener { remove(dataSourceListener) }
        dataSourceListener = nil
        devices = []
        current = nil
    }

    /// Makes a device the default output, like choosing it in Control Center.
    func select(_ device: AudioOutputDevice) {
        var id = device.id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        if status != noErr { log.error("Couldn't switch output to \(device.name, privacy: .public): \(status)") }
    }

    // MARK: Reading

    private func reload() {
        let outputs = Self.deviceIDs().compactMap(Self.describe)
        let defaultID = Self.defaultOutputID()
        let next = outputs.first { $0.id == defaultID }
        if outputs != devices { devices = outputs }
        if next != current { current = next }
        watchDataSource(of: next)
    }

    /// The built-in output switches between speakers and the headphone jack
    /// without changing device, so that's watched separately.
    private func watchDataSource(of device: AudioOutputDevice?) {
        guard dataSourceListener?.object != device?.id else { return }
        if let dataSourceListener { remove(dataSourceListener) }
        dataSourceListener = nil
        guard let device, device.transport == .builtIn else { return }
        dataSourceListener = listen(device.id, selector: kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
    }

    private func listen(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Listener? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        return Listener(object: object, address: address, block: block)
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
    }

    // MARK: CoreAudio properties

    private static func deviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultOutputID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    /// Nil for devices that aren't outputs a user can pick.
    private static func describe(_ id: AudioObjectID) -> AudioOutputDevice? {
        guard hasOutputStreams(id),
              uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput) == 1,
              uint32(id, kAudioDevicePropertyIsHidden) != 1,
              let name = string(id, kAudioObjectPropertyName),
              let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let transport = Self.transport(uint32(id, kAudioDevicePropertyTransportType) ?? 0)
        // 'hdpn': the built-in output is the headphone jack.
        let headphones = transport == .builtIn
            && uint32(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput) == 0x6864_706E
        return AudioOutputDevice(id: id, uid: uid, name: name, transport: transport, isHeadphonesDataSource: headphones)
    }

    private static func transport(_ value: UInt32) -> AudioOutputDevice.Transport {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeHDMI: .hdmi
        case kAudioDeviceTransportTypeDisplayPort: .displayPort
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        case kAudioDeviceTransportTypeVirtual: .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: .aggregate
        default: .other
        }
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
