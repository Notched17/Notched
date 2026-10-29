// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// The symbol the HUD shows for a level.
@Suite("HUDGlyph")
struct HUDGlyphTests {
    @Test("Volume: a slash when silent, then one, two and three waves")
    func volumeSymbols() {
        #expect(HUDGlyph.symbol(kind: .volume, level: 0, isMuted: false) == "speaker.slash.fill")
        #expect(HUDGlyph.symbol(kind: .volume, level: 0.0625, isMuted: false) == "speaker.wave.1.fill")
        #expect(HUDGlyph.symbol(kind: .volume, level: 0.3125, isMuted: false) == "speaker.wave.1.fill")
        #expect(HUDGlyph.symbol(kind: .volume, level: 0.375, isMuted: false) == "speaker.wave.2.fill")
        #expect(HUDGlyph.symbol(kind: .volume, level: 0.625, isMuted: false) == "speaker.wave.2.fill")
        #expect(HUDGlyph.symbol(kind: .volume, level: 0.6875, isMuted: false) == "speaker.wave.3.fill")
        #expect(HUDGlyph.symbol(kind: .volume, level: 1, isMuted: false) == "speaker.wave.3.fill")
    }

    @Test("Muted shows the slash whatever the level")
    func mutedIsSlashed() {
        #expect(HUDGlyph.symbol(kind: .volume, level: 0.8, isMuted: true) == "speaker.slash.fill")
    }

    @Test("Brightness: a small sun up to half, a full one above")
    func brightnessSymbols() {
        #expect(HUDGlyph.symbol(kind: .brightness, level: 0.0, isMuted: false) == "sun.min.fill")
        #expect(HUDGlyph.symbol(kind: .brightness, level: 0.5, isMuted: false) == "sun.min.fill")
        #expect(HUDGlyph.symbol(kind: .brightness, level: 0.5625, isMuted: false) == "sun.max.fill")
    }
}
