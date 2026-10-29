// SPDX-License-Identifier: GPL-3.0-or-later

import AudioToolbox
import CoreAudio

/// The default output device's volume and mute, through the audio HAL. Reads
/// and writes are thread-safe, so the tap thread calls them directly.
///
/// The volume is the device's "virtual main volume", which is what the volume
/// keys move. An output that doesn't have one, or won't let it be set (many
/// HDMI and DisplayPort outputs), reports not settable and the key goes to macOS.
struct CoreAudioVolumeControl: LevelControl, MuteControl {
    func currentTarget() -> UInt32? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    func isSettable(_ id: UInt32) -> Bool {
        var address = Self.volumeAddress
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    func level(_ id: UInt32) -> Double? {
        var address = Self.volumeAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    func setLevel(_ value: Double, on id: UInt32) -> Bool {
        var address = Self.volumeAddress
        var scalar = Float32(max(0, min(1, value)))
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr
    }

    func isMuted(_ id: UInt32) -> Bool? {
        var address = Self.muteAddress
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    func setMuted(_ muted: Bool, on id: UInt32) -> Bool {
        var address = Self.muteAddress
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
    }
}
