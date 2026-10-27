// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

@Suite("DisplaySelection")
struct DisplaySelectionTests {
    static let builtIn = DisplayCandidate(id: "BUILTIN", isBuiltIn: true, hasNotch: true)
    static let externalPrimary = DisplayCandidate(id: "EXT-1", isBuiltIn: false, hasNotch: false)
    static let external2 = DisplayCandidate(id: "EXT-2", isBuiltIn: false, hasNotch: false)

    @Test("Main prefers the built-in notched display even when an external display is primary")
    func mainPrefersNotchedBuiltIn() {
        let screens = [Self.externalPrimary, Self.builtIn, Self.external2]
        #expect(DisplaySelection.main.resolve(among: screens) == ["BUILTIN"])
    }

    @Test("Main falls back to the primary display (first in the list) when no notched built-in is connected")
    func mainFallsBackToPrimary() {
        let screens = [Self.externalPrimary, Self.external2]
        #expect(DisplaySelection.main.resolve(among: screens) == ["EXT-1"])
    }

    @Test("A built-in display without a notch does not beat the primary display")
    func builtInWithoutNotchIsNotPreferred() {
        let oldLaptop = DisplayCandidate(id: "OLD", isBuiltIn: true, hasNotch: false)
        #expect(DisplaySelection.main.resolve(among: [Self.externalPrimary, oldLaptop]) == ["EXT-1"])
    }

    @Test("All displays returns every display in order")
    func allDisplays() {
        let screens = [Self.externalPrimary, Self.builtIn, Self.external2]
        #expect(DisplaySelection.all.resolve(among: screens) == ["EXT-1", "BUILTIN", "EXT-2"])
    }

    @Test("A specific display is used when it is connected")
    func specificConnected() {
        let screens = [Self.externalPrimary, Self.builtIn, Self.external2]
        #expect(DisplaySelection.specific("EXT-2").resolve(among: screens) == ["EXT-2"])
    }

    @Test("A specific display that is disconnected falls back to Main")
    func specificDisconnectedFallsBack() {
        let screens = [Self.externalPrimary, Self.builtIn]
        #expect(DisplaySelection.specific("EXT-2").resolve(among: screens) == ["BUILTIN"])
    }

    @Test("No screens resolves to nothing")
    func noScreens() {
        #expect(DisplaySelection.main.resolve(among: []).isEmpty)
    }
}
