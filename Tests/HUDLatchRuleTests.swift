// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// Whether the HUD starts latched off after crashes while it was armed (§7).
@Suite("HUDLatchRule")
struct HUDLatchRuleTests {
    @Test("Two sessions in a row that crashed while armed latch the HUD")
    func twoArmedCrashesInARowLatch() {
        let first = HUDLatchRule.judgeLaunch(previousSessionCrashed: true, wasArmed: true, streak: 0)
        #expect(first.streak == 1)
        #expect(first.latch == false)
        let second = HUDLatchRule.judgeLaunch(previousSessionCrashed: true, wasArmed: true, streak: first.streak)
        #expect(second.streak == 2)
        #expect(second.latch == true)
    }

    @Test("It stays latched while the crashes continue")
    func latchPersistsWhileCrashesContinue() {
        let third = HUDLatchRule.judgeLaunch(previousSessionCrashed: true, wasArmed: true, streak: 2)
        #expect(third.latch == true)
        #expect(third.streak == 3)
    }

    @Test("A clean exit starts the count again")
    func cleanExitResetsStreak() {
        let result = HUDLatchRule.judgeLaunch(previousSessionCrashed: false, wasArmed: true, streak: 1)
        #expect(result.streak == 0)
        #expect(result.latch == false)
    }

    @Test("A crash while the HUD wasn't armed isn't the HUD's")
    func crashWhileUnarmedResetsStreak() {
        let result = HUDLatchRule.judgeLaunch(previousSessionCrashed: true, wasArmed: false, streak: 1)
        #expect(result.streak == 0)
        #expect(result.latch == false)
    }
}
