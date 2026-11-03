// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

@Suite("Today weather wrapped around the camera housing")
struct NotchWrapTests {
    private func make(isNotch: Bool = true, theme: IslandTheme = .notchBlack, scale: Double) -> NotchWrap? {
        NotchWrap.make(isNotch: isNotch, theme: theme, scale: scale, headerHeight: 38, notchGap: 224)
    }

    @Test("Notch Black at 110% or more wraps, with the housing's width left clear")
    func wraps() throws {
        for scale in [1.1, 1.15, 1.25] {
            let wrap = try #require(make(scale: scale))
            #expect(wrap.gap == 224)
            // Starts a few points from the island's top edge, not under the notch's bottom.
            #expect(abs((38 + IslandMetrics.expandedNotchGap - wrap.rise) - NotchWrap.top) < 0.001)
        }
    }

    @Test("Not below 110%, not on a glass theme, not on a display without a notch")
    func doesNotWrap() {
        #expect(make(scale: 1.05) == nil)
        #expect(make(scale: 0.85) == nil)
        #expect(make(theme: .liquidGlass, scale: 1.25) == nil)
        #expect(make(theme: .tintedGlass, scale: 1.1) == nil)
        #expect(make(isNotch: false, scale: 1.25) == nil)
    }

    @Test("The slider's 110% still counts after floating-point storage")
    func floatingPoint() {
        #expect(make(scale: 1.1000000000000001) != nil)
        #expect(make(scale: 1.0999999999999999) != nil)
    }
}
