// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// The banner a volume or brightness reading becomes.
@MainActor
@Suite("HUDBanner")
struct HUDBannerTests {
    private func reading(_ level: Double, kind: HUDKind = .volume, muted: Bool = false, atLimit: Bool = false) -> HUDReading {
        HUDReading(kind: kind, targetID: 7, level: level, isMuted: muted, atLimit: atLimit)
    }

    @Test("A volume banner is one category, above every other banner, and short")
    func volumeBannerBasics() {
        let banner = HUDBanner.make(reading: reading(0.5625), device: nil, serial: 1)
        #expect(banner.id == "hud.volume")
        #expect(banner.moduleID == "hud")
        #expect(banner.priority == .hud)
        #expect(banner.duration == .seconds(1.5))
        #expect(banner.trailing != nil)
    }

    @Test("Brightness is its own category, so it replaces a volume HUD at once")
    func brightnessBannerId() {
        #expect(HUDBanner.make(reading: reading(0.4, kind: .brightness), device: nil, serial: 1).id == "hud.brightness")
    }

    @Test("VoiceOver hears the level as a percentage, or muted")
    func accessibilityLabels() {
        #expect(HUDBanner.make(reading: reading(0.5625), device: nil, serial: 1).accessibilityLabel == "Volume 56 percent")
        #expect(HUDBanner.make(reading: reading(1.0, atLimit: true), device: nil, serial: 1).accessibilityLabel == "Volume 100 percent")
        #expect(HUDBanner.make(reading: reading(0.5, muted: true), device: nil, serial: 1).accessibilityLabel == "Volume muted")
        #expect(HUDBanner.make(reading: reading(0.4, kind: .brightness), device: nil, serial: 1).accessibilityLabel == "Brightness 40 percent")
    }
}
