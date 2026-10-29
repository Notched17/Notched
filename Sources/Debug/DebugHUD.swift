// SPDX-License-Identifier: GPL-3.0-or-later
//
// M3b Part B, Task 7: arms the media-key tap by hand so it can be exercised
// before the HUD module exists. Replaced by `HUDModule` in Task 9, and the
// `hud-arm` command goes with it. DEBUG only.

#if DEBUG
import AppKit
import CoreGraphics

@MainActor
enum DebugHUD {
    private static var tap: MediaKeyTap?
    private static var engine: HUDKeyEngine?
    private static var autoDisarm: Task<Void, Never>?

    /// Arms the tap for `seconds` (a hand-armed tap always disarms itself), so
    /// a forgotten one can never sit in the keyboard's path.
    static func arm(_ on: Bool, seconds: Double) {
        autoDisarm?.cancel()
        autoDisarm = nil
        if let engine, let tap {
            engine.send(.armed(false))
            tap.setEnabled(false)
            tap.remove()
            Self.tap = nil
            Self.engine = nil
            probeLog.notice("hud: disarmed")
        }
        guard on else { return }
        let engine = HUDKeyEngine(volume: CoreAudioVolumeControl(), brightness: nil) { effects in
            for effect in effects { probeLog.notice("hud: effect \(String(describing: effect), privacy: .public)") }
        }
        let tap = MediaKeyTap(engine: engine)
        guard tap.install() else {
            probeLog.notice("hud: couldn't install the tap")
            return
        }
        Self.engine = engine
        Self.tap = tap
        engine.send(.armed(true))
        engine.send(.visible(true))
        engine.send(.trust(true))
        probeLog.notice("hud: armed for \(seconds, privacy: .public) s")
        autoDisarm = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            arm(false, seconds: 0)
        }
    }

    /// Posts a volume or brightness key as the keyboard would: a system-defined
    /// event at the HID tap, a down, `repeats` auto-repeats, then an up.
    static func postKey(_ name: String, shift: Bool, option: Bool, repeats: Int) {
        guard let code = keyCodes[name] else {
            probeLog.error("hud-key: unknown key \(name, privacy: .public)")
            return
        }
        var modifiers: UInt = 0
        if shift { modifiers |= 0x20000 }
        if option { modifiers |= 0x80000 }
        Task { @MainActor in
            post(code, down: true, isRepeat: false, modifiers: modifiers)
            for _ in 0..<repeats {
                try? await Task.sleep(for: .milliseconds(30))
                post(code, down: true, isRepeat: true, modifiers: modifiers)
            }
            try? await Task.sleep(for: .milliseconds(30))
            post(code, down: false, isRepeat: false, modifiers: modifiers)
        }
    }

    /// Blocks the main thread for `milliseconds`. With `key`, a key is posted from a background
    /// thread half a second in, to show the tap decides without waiting for main.
    static func hang(milliseconds: Double, key: String?) {
        if let key, let code = keyCodes[key] {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                post(code, down: true, isRepeat: false, modifiers: 0)
                post(code, down: false, isRepeat: false, modifiers: 0)
                probeLog.notice("hang: key posted while main is blocked")
            }
        }
        probeLog.notice("hang: blocking main for \(milliseconds, privacy: .public) ms")
        Thread.sleep(forTimeInterval: milliseconds / 1000)
        probeLog.notice("hang: main is back")
    }

    private static let keyCodes = ["up": 0, "down": 1, "bup": 2, "bdown": 3, "mute": 7]

    nonisolated private static func post(_ code: Int, down: Bool, isRepeat: Bool, modifiers: UInt) {
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: modifiers | UInt(state << 8)),
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            subtype: 8, data1: (code << 16) | (state << 8) | (isRepeat ? 1 : 0), data2: -1
        )
        guard let cgEvent = event?.cgEvent else { return }
        cgEvent.flags = CGEventFlags(rawValue: UInt64(modifiers))
        cgEvent.post(tap: .cghidEventTap)
    }
}
#endif
