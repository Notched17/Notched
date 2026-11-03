// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Small typed reads of Core Audio properties, for the mixer (#17).
enum CAProperty {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = Self.address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func value<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as _: T.Type) -> T? {
        var address = Self.address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func defaultOutput() -> AudioObjectID? {
        value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self)
            .flatMap { $0 == 0 ? nil : $0 }
    }
}

/// One audio process Core Audio knows about, and the app it belongs to.
struct AudioProcess: Equatable, Sendable {
    let object: AudioObjectID
    let pid: pid_t
    /// The app's bundle id: the process's own, or, for a helper (Safari's WebKit GPU
    /// process), the app macOS holds responsible for it.
    let appID: String
    let isRunningOutput: Bool

    /// Every audio process except Notched's own. Reads Core Audio and the
    /// process table; safe from any thread.
    static func all() -> [AudioProcess] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        return CAProperty.ids(system, kAudioHardwarePropertyProcessObjectList).compactMap { object in
            guard let pid = CAProperty.value(object, kAudioProcessPropertyPID, as: pid_t.self), pid != getpid() else { return nil }
            let responsible = ResponsibleProcess.pid(responsibleFor: pid).flatMap { $0 == pid ? nil : $0 }
            let ownBundle = CAProperty.string(object, kAudioProcessPropertyBundleID)
            let responsibleBundle = responsible.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            guard let appID = responsibleBundle ?? ownBundle, !appID.isEmpty else { return nil }
            return AudioProcess(
                object: object, pid: pid, appID: appID,
                isRunningOutput: CAProperty.value(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            )
        }
    }

    /// The process objects of one app (all its helpers included).
    static func objects(of app: String) -> [AudioObjectID] {
        all().filter { $0.appID == app }.map(\.object)
    }
}
