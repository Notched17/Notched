// SPDX-License-Identifier: GPL-3.0-or-later

/// One volume or brightness key press, decoded from a system-defined event
/// (`NX_SYSDEFINED`, subtype 8). Pure: the tap hands over the numbers.
struct MediaKeyEvent: Equatable, Sendable {
    /// The `NX_KEYTYPE_*` codes the HUD handles. Every other media key (play,
    /// keyboard backlight) isn't ours and never decodes.
    enum Key: Int, Sendable {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    enum Phase: Sendable {
        case down, up
    }

    /// The modifier keys that change what a press means: Shift inverts the
    /// feedback sound, Shift+Option is a fine step, Option alone opens System
    /// Settings. Fn, Caps Lock and the keypad flag are ignored.
    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    let key: Key
    let phase: Phase
    let isRepeat: Bool
    let modifiers: Modifiers

    /// Decodes `NSEvent.subtype`, `NSEvent.data1` and the `CGEventFlags` raw
    /// value. Nil for anything that isn't a down or up of one of `Key`.
    static func parse(subtype: Int, data1: Int, flags: UInt64) -> MediaKeyEvent? {
        guard subtype == 8, let key = Key(rawValue: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let phase: Phase
        switch (data1 & 0xFF00) >> 8 {
        case 0x0A: phase = .down
        case 0x0B: phase = .up
        default: return nil
        }
        var modifiers: Modifiers = []
        if flags & 0x2_0000 != 0 { modifiers.insert(.shift) }
        if flags & 0x4_0000 != 0 { modifiers.insert(.control) }
        if flags & 0x8_0000 != 0 { modifiers.insert(.option) }
        if flags & 0x10_0000 != 0 { modifiers.insert(.command) }
        return MediaKeyEvent(key: key, phase: phase, isRepeat: data1 & 0x1 == 1, modifiers: modifiers)
    }
}
