// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// Decoding the system-defined events that carry the volume and brightness keys (#20).
@Suite("MediaKeyEvent")
struct MediaKeyEventTests {
    @Test("Volume Up going down")
    func soundUpDown() {
        let event = MediaKeyEvent.parse(subtype: 8, data1: 0x0A00, flags: 0)
        #expect(event == MediaKeyEvent(key: .soundUp, phase: .down, isRepeat: false, modifiers: []))
    }

    @Test("The repeat bit marks an auto-repeat")
    func repeatDown() {
        #expect(MediaKeyEvent.parse(subtype: 8, data1: 0x0A01, flags: 0)?.isRepeat == true)
    }

    @Test("Mute going up")
    func muteUp() {
        let event = MediaKeyEvent.parse(subtype: 8, data1: 0x70B00, flags: 0)
        #expect(event?.key == .mute)
        #expect(event?.phase == .up)
    }

    @Test("The brightness keys")
    func brightnessKeys() {
        #expect(MediaKeyEvent.parse(subtype: 8, data1: 0x20A00, flags: 0)?.key == .brightnessUp)
        #expect(MediaKeyEvent.parse(subtype: 8, data1: 0x30B00, flags: 0)?.key == .brightnessDown)
    }

    @Test("Another subtype (the auxiliary mouse buttons) is not a media key")
    func unknownSubtypeIsNil() {
        #expect(MediaKeyEvent.parse(subtype: 7, data1: 0x0A00, flags: 0) == nil)
    }

    @Test("Keys that aren't ours (play, keyboard backlight) are nil")
    func unknownKeyIsNil() {
        #expect(MediaKeyEvent.parse(subtype: 8, data1: 0x100A00, flags: 0) == nil)
        #expect(MediaKeyEvent.parse(subtype: 8, data1: 0x150A00, flags: 0) == nil)
    }

    @Test("A state that is neither down nor up is nil")
    func unknownStateIsNil() {
        #expect(MediaKeyEvent.parse(subtype: 8, data1: 0x0C00, flags: 0) == nil)
    }

    @Test("Shift and Option are read from the flags")
    func modifiers() {
        let event = MediaKeyEvent.parse(subtype: 8, data1: 0x0A00, flags: 0xA0000)
        #expect(event?.modifiers == [.shift, .option])
    }

    @Test("Control and Command are read too")
    func controlAndCommand() {
        let event = MediaKeyEvent.parse(subtype: 8, data1: 0x0A00, flags: 0x140000)
        #expect(event?.modifiers == [.control, .command])
    }

    @Test("Fn, Caps Lock and the keypad flag aren't modifiers we care about")
    func ignoresFnAndCapsLockFlags() {
        let event = MediaKeyEvent.parse(subtype: 8, data1: 0x0A00, flags: 0x800000 | 0x10000 | 0x200000)
        #expect(event?.modifiers == [])
    }
}
