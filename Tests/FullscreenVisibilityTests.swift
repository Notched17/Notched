// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// Whether the island hides over a fullscreen app (#5), including the
/// "Keep showing while media plays" exception from M2.
@Suite("FullscreenVisibility")
struct FullscreenVisibilityTests {
    @Test func notFullscreenNeverHides() {
        #expect(!FullscreenVisibility.shouldHide(isFullscreen: false, hideInFullscreen: true, keepForMedia: true, anyActivityKeepsIsland: false))
    }

    @Test func fullscreenHidesByDefault() {
        #expect(FullscreenVisibility.shouldHide(isFullscreen: true, hideInFullscreen: true, keepForMedia: true, anyActivityKeepsIsland: false))
    }

    @Test func playingMediaKeepsIsland() {
        #expect(!FullscreenVisibility.shouldHide(isFullscreen: true, hideInFullscreen: true, keepForMedia: true, anyActivityKeepsIsland: true))
    }

    @Test func settingOffStillHides() {
        #expect(FullscreenVisibility.shouldHide(isFullscreen: true, hideInFullscreen: true, keepForMedia: false, anyActivityKeepsIsland: true))
    }

    @Test func hideInFullscreenOffNeverHides() {
        #expect(!FullscreenVisibility.shouldHide(isFullscreen: true, hideInFullscreen: false, keepForMedia: false, anyActivityKeepsIsland: false))
    }
}
