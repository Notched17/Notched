// SPDX-License-Identifier: GPL-3.0-or-later
//
// Spike B1 (M3b Part B), experiments 1 and 2: does swallowing a volume key at a
// session tap suppress the Control Center HUD on macOS 27.2, and which
// permissions does that tap need? DEBUG only; removed in Task 10 once ADR-0019
// is written.
//
// Safety: the tap passes every event back untouched except the Volume Up
// events this probe posts itself (tagged in `eventSourceUserData`), and it
// removes itself after 30 s. Real key presses are never swallowed.

#if DEBUG
import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics

@MainActor
enum HUDTapProbe {
    /// "NOTC": marks the events this probe posted.
    nonisolated static let tag: Int64 = 0x4E4F5443
    nonisolated static let step: Float = 1.0 / 16.0

    final class Context: @unchecked Sendable {
        let swallow: Bool
        init(swallow: Bool) { self.swallow = swallow }
    }

    static func run(swallow: Bool) {
        let trusted = AXIsProcessTrusted()
        probeLog.notice("hudtap: swallow=\(swallow) AXIsProcessTrusted=\(trusted) listenAccess=\(CGPreflightListenEventAccess()) postAccess=\(CGPreflightPostEventAccess())")
        if !trusted { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
        let context = Context(swallow: swallow)
        Thread.detachNewThread { runTap(context) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            for _ in 0..<3 {
                post(key: 0, down: true)
                post(key: 0, down: false)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private static func post(key: Int, down: Bool) {
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            subtype: 8, data1: (key << 16) | (state << 8), data2: -1
        )
        guard let cgEvent = event?.cgEvent else { return }
        cgEvent.setIntegerValueField(.eventSourceUserData, value: tag)
        cgEvent.post(tap: .cghidEventTap)
    }

    // MARK: Tap thread

    private nonisolated static func runTap(_ context: Context) {
        let initial = outputVolume()
        let info = Unmanaged.passUnretained(context).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: 1 << 14, callback: callback, userInfo: info
        ) else {
            probeLog.notice("hudtap: tapCreate returned nil (the tap needs a permission Notched doesn't have yet)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        probeLog.notice("hudtap: tap installed; volume \(initial ?? -1)")
        withExtendedLifetime(context) {
            _ = CFRunLoopRunInMode(.defaultMode, 30, false)
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        if let initial { _ = setOutputVolume(initial) }
        probeLog.notice("hudtap: tap removed; volume restored to \(initial ?? -1)")
    }

    private nonisolated static let callback: CGEventTapCallBack = { _, type, event, info in
        let pass = Unmanaged.passUnretained(event)
        guard let info else { return pass }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            probeLog.error("hudtap: tap disabled (\(type.rawValue))")
            return pass
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
        let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
        let key = (ns.data1 & 0xFFFF0000) >> 16
        let state = (ns.data1 & 0xFF00) >> 8
        let tagged = event.getIntegerValueField(.eventSourceUserData) == HUDTapProbe.tag
        probeLog.notice("hudtap: event key=\(key) state=\(state) tagged=\(tagged)")
        guard tagged, key == 0 else { return pass }
        guard context.swallow else { return pass }
        if state == 0xA, let before = outputVolume() {
            let ok = setOutputVolume(min(1, before + HUDTapProbe.step))
            probeLog.notice("hudtap: swallowed Volume Up; \(before) -> \(outputVolume() ?? -1) set=\(ok)")
        }
        return nil
    }

    // MARK: CoreAudio

    private nonisolated static func outputDevice() -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private nonisolated static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private nonisolated static func outputVolume() -> Float? {
        guard let device = outputDevice() else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var address = volumeAddress
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private nonisolated static func setOutputVolume(_ volume: Float) -> Bool {
        guard let device = outputDevice() else { return false }
        var value = max(0, min(1, volume))
        var address = volumeAddress
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value) == noErr
    }
}
#endif
