// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The four ways the HUD can look (#23), and the choice being kept.
@MainActor
@Suite("HUDStyle")
struct HUDStyleTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "HUDStyleTests.\(UUID().uuidString)")! }

    @Test("Inline is the default, as the notch's own look")
    func defaultIsInline() {
        #expect(HUDSettings(defaults: defaults()).style == .inline)
    }

    @Test("All four styles are offered, in order, each with its own name")
    func fourStylesWithTitles() {
        #expect(HUDStyle.allCases == [.inline, .vertical, .circular, .minimal])
        #expect(Set(HUDStyle.allCases.map(\.title)).count == 4)
    }

    @Test("The choice survives a relaunch")
    func styleRoundTripsThroughSettings() {
        let store = defaults()
        let settings = HUDSettings(defaults: store)
        settings.style = .circular
        #expect(HUDSettings(defaults: store).style == .circular)
    }

    @Test("A style this version doesn't know falls back to inline")
    func unknownStyleFallsBack() {
        let store = defaults()
        store.set("spinning", forKey: HUDSettings.Key.style)
        #expect(HUDSettings(defaults: store).style == .inline)
    }

    @Test("Every style has a right-hand side, except the ring when there's no output icon to show")
    func trailingSideByStyle() {
        for style in [HUDStyle.inline, .vertical, .minimal] {
            #expect(HUDBanner.hasTrailing(style: style, deviceSymbol: nil))
        }
        #expect(!HUDBanner.hasTrailing(style: .circular, deviceSymbol: nil))
        #expect(HUDBanner.hasTrailing(style: .circular, deviceSymbol: "laptopcomputer"))
    }

    @Test("The banner is the same category whatever the style, so changing it mid-press can't leave two up")
    func idDoesNotDependOnStyle() {
        let reading = HUDReading(kind: .volume, targetID: 7, level: 0.5, isMuted: false, atLimit: false)
        for style in HUDStyle.allCases {
            #expect(HUDBanner.make(reading: reading, device: nil, serial: 1, style: style).id == "hud.volume")
        }
    }

    @Test("The circular banner has no right-hand side when it has no output to show")
    func circularBannerHasNoTrailingWithoutDevice() {
        let reading = HUDReading(kind: .brightness, targetID: 1, level: 0.5, isMuted: false, atLimit: false)
        #expect(HUDBanner.make(reading: reading, device: nil, serial: 1, style: .circular).trailing == nil)
        #expect(HUDBanner.make(reading: reading, device: nil, serial: 1, style: .minimal).trailing != nil)
    }
}
