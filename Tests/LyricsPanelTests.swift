// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import Notched

@Suite("Lyrics tab placement")
struct LyricsPanelTests {
    private let size = CGSize(width: 400, height: 220)

    @Test("On a notched display the card starts a gap below the notch")
    func belowNotch() {
        let inset = LyricsPanelController.topInset(safeAreaTop: 37.5, menuBarHeight: 37.5)
        #expect(inset == 37.5 + LyricsPanelController.gap)
    }

    @Test("Without a notch it starts under the floating pill, which sits under the menu bar")
    func belowPill() {
        let inset = LyricsPanelController.topInset(safeAreaTop: 0, menuBarHeight: 24)
        #expect(inset == 24 + LyricsPanelController.pillGap + LyricsPanelController.pillHeight + LyricsPanelController.gap)
    }

    @Test("It is centred on the screen, with its top at the inset")
    func centred() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = LyricsPanelController.frame(screenFrame: screen, topInset: 46, size: size)
        #expect(abs(frame.midX - 756) < 0.001)
        #expect(abs(frame.maxY - 936) < 0.001)
        #expect(frame.size == size)
    }

    @Test("On a screen to the right of another it centres on its own frame")
    func secondScreen() {
        let screen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let frame = LyricsPanelController.frame(screenFrame: screen, topInset: 46, size: size)
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY - 46)
    }

    @Test("A screen narrower than the card shrinks it and keeps it on the screen")
    func narrowScreen() {
        let screen = CGRect(x: 100, y: 0, width: 300, height: 600)
        let frame = LyricsPanelController.frame(screenFrame: screen, topInset: 46, size: size)
        #expect(frame.minX >= screen.minX)
        #expect(frame.maxX <= screen.maxX)
        #expect(frame.width == 300)
    }
}
