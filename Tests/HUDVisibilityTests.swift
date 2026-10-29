// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// When the HUD may take a key (the safety design §3.1): only if the island
/// can show it right now.
@Suite("HUDVisibility")
struct HUDVisibilityTests {
    @Test("Only a shown island that isn't paused, suspended, alerting or in use can show the HUD")
    func canShowTable() {
        for bits in 0..<32 {
            let paused = bits & 1 != 0
            let suspended = bits & 2 != 0
            let shown = bits & 4 != 0
            let alert = bits & 8 != 0
            let interacting = bits & 16 != 0
            let expected = !paused && !suspended && shown && !alert && !interacting
            #expect(HUDVisibility.canShow(paused: paused, suspended: suspended, anyIslandShown: shown,
                                          alertShowing: alert, interacting: interacting) == expected,
                    "paused=\(paused) suspended=\(suspended) shown=\(shown) alert=\(alert) interacting=\(interacting)")
        }
    }
}

@MainActor
@Suite("IslandPresence")
struct IslandPresenceTests {
    @Test("Nothing is shown at first, so the HUD can't show")
    func startsClosed() {
        #expect(IslandPresence().canShowHUD == false)
    }

    @Test("Each input moves the answer")
    func inputsMoveTheAnswer() {
        let sut = IslandPresence()
        sut.anyIslandShown = true
        #expect(sut.canShowHUD == true)
        sut.isInteracting = true
        #expect(sut.canShowHUD == false)
        sut.isInteracting = false
        sut.alertShowing = true
        #expect(sut.canShowHUD == false)
        sut.alertShowing = false
        sut.isPaused = true
        #expect(sut.canShowHUD == false)
        sut.isPaused = false
        #expect(sut.canShowHUD == true)
    }

    @Test("Suspension (lock, sleep, another user) is exposed on its own, and closes the HUD too")
    func suspensionIsExposed() {
        let sut = IslandPresence()
        sut.anyIslandShown = true
        sut.isSuspended = true
        #expect(sut.isSuspended == true)
        #expect(sut.canShowHUD == false)
        sut.isSuspended = false
        #expect(sut.canShowHUD == true)
    }
}
