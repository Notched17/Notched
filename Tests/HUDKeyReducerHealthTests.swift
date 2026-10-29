// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// When the tap is re-enabled, when it is taken away for good, and when a
/// kind of key is left to macOS (the safety design §4 and §5).
@Suite("HUDKeyReducer health")
struct HUDKeyReducerHealthTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func armed() -> HUDKeyReducer {
        var sut = HUDKeyReducer()
        for event: HUDKeyReducer.Event in [.armed(true), .visible(true), .trust(true)] {
            _ = sut.reduce(event, now: start)
        }
        return sut
    }

    private func down(_ key: MediaKeyEvent.Key = .soundUp) -> HUDKeyReducer.Event {
        .keyDown(MediaKeyEvent(key: key, phase: .down, isRepeat: false, modifiers: []))
    }

    /// A whole press whose apply ends in `outcome`; returns what the apply's result produced.
    @discardableResult
    private func press(_ sut: inout HUDKeyReducer, _ outcome: ApplyOutcome) -> [HUDKeyReducer.Effect] {
        _ = sut.reduce(down(), now: start)
        let effects = sut.reduce(.applied(outcome), now: start)
        _ = sut.reduce(.keyUp(.soundUp), now: start)
        return effects
    }

    private let changed = ApplyOutcome.changed(HUDReading(kind: .volume, targetID: 7, level: 0.5625, isMuted: false, atLimit: false))

    // MARK: The tap being switched off by the system

    @Test("The first timeout re-enables the tap")
    func firstTimeoutReEnables() {
        var sut = armed()
        #expect(sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(0)) == [.reEnableTap])
    }

    @Test("A second timeout within ten minutes removes the tap and latches")
    func secondTimeoutWithinTenMinutesTripsAndLatches() {
        var sut = armed()
        _ = sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(0))
        #expect(sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(599)) == [.removeTap(.timeouts), .latch(.timeouts)])
    }

    @Test("Timeouts more than ten minutes apart are separate incidents")
    func timeoutsElevenMinutesApartDontTrip() {
        var sut = armed()
        #expect(sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(0)) == [.reEnableTap])
        #expect(sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(660)) == [.reEnableTap])
    }

    @Test("A disable by user input is re-enabled, however often, and never counts")
    func userInputDisableReEnables() {
        var sut = armed()
        for second in 0..<6 {
            #expect(sut.reduce(.tapDisabled(byTimeout: false, trusted: true), now: at(Double(second))) == [.reEnableTap])
        }
        #expect(sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(7)) == [.reEnableTap])
    }

    @Test("A tap that is switched off while the HUD isn't armed stays off")
    func disabledWhileUnarmedIsNotReEnabled() {
        var sut = HUDKeyReducer()
        #expect(sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(0)).isEmpty)
        var paused = armed()
        _ = paused.reduce(.armed(false), now: at(0))
        #expect(paused.reduce(.tapDisabled(byTimeout: false, trusted: true), now: at(1)).isEmpty)
    }

    // MARK: A press the tap stops seeing

    /// Down swallowed, then the tap stops seeing events for a while.
    private func pressInterrupted(by event: HUDKeyReducer.Event) -> [HUDKeyReducer.Effect] {
        var sut = armed()
        _ = sut.reduce(down(), now: start)
        _ = sut.reduce(.applied(changed), now: start)
        _ = sut.reduce(event, now: at(1))
        return sut.reduce(.keyUp(.soundUp), now: at(1))
    }

    @Test("If macOS switched the tap off mid-press, macOS gets the key-up, so no key is left held down")
    func keyUpPassesAfterTapDisabledMidPress() {
        #expect(pressInterrupted(by: .tapDisabled(byTimeout: true, trusted: true)) == [.pass])
        #expect(pressInterrupted(by: .tapDisabled(byTimeout: false, trusted: true)) == [.pass])
    }

    @Test("The same when the HUD is disarmed, hidden or loses permission mid-press")
    func keyUpPassesAfterStateChangeMidPress() {
        #expect(pressInterrupted(by: .armed(false)) == [.pass])
        #expect(pressInterrupted(by: .visible(false)) == [.pass])
        #expect(pressInterrupted(by: .trust(false)) == [.pass])
    }

    @Test("A press that begins after the tap is back is paired normally")
    func pairingResumesAfterTapDisabled() {
        var sut = armed()
        _ = sut.reduce(.tapDisabled(byTimeout: true, trusted: true), now: at(0))
        _ = sut.reduce(down(), now: at(1))
        _ = sut.reduce(.applied(changed), now: at(1))
        #expect(sut.reduce(.keyUp(.soundUp), now: at(1)) == [.swallow])
    }

    // MARK: Permission

    @Test("Losing the permission removes the tap, without latching")
    func trustLostRemovesTapWithoutLatch() {
        var viaTrust = armed()
        #expect(viaTrust.reduce(.trust(false), now: at(0)) == [.removeTap(.permissionRevoked)])
        var viaDisable = armed()
        #expect(viaDisable.reduce(.tapDisabled(byTimeout: true, trusted: false), now: at(0)) == [.removeTap(.permissionRevoked)])
    }

    @Test("The tap is removed once, however many checks notice the permission gone")
    func trustLossIsReportedOnce() {
        var sut = armed()
        _ = sut.reduce(.trust(false), now: at(0))
        #expect(sut.reduce(.trust(false), now: at(2)).isEmpty)
        #expect(sut.reduce(.tapDisabled(byTimeout: true, trusted: false), now: at(3)).isEmpty)
    }

    @Test("Once the tap is removed, every key goes to macOS")
    func everythingPassesAfterRemoval() {
        var sut = armed()
        _ = sut.reduce(.trust(false), now: at(0))
        _ = sut.reduce(.trust(true), now: at(1))
        #expect(sut.reduce(down(), now: at(2)) == [.pass])
        #expect(sut.reduce(.keyUp(.soundUp), now: at(2)) == [.pass])
    }

    // MARK: Slow callbacks

    @Test("Three slow callbacks within a minute remove the tap and latch")
    func threeSlowCallbacksTrip() {
        var sut = armed()
        #expect(sut.reduce(.callbackTook(0.06), now: at(0)).isEmpty)
        #expect(sut.reduce(.callbackTook(0.06), now: at(10)).isEmpty)
        #expect(sut.reduce(.callbackTook(0.06), now: at(20)) == [.removeTap(.slowCallbacks), .latch(.slowCallbacks)])
    }

    @Test("Callbacks under 50 ms never count")
    func fastCallbacksNeverCount() {
        var sut = armed()
        for second in 0..<100 {
            #expect(sut.reduce(.callbackTook(0.049), now: at(Double(second))).isEmpty)
        }
    }

    @Test("Slow callbacks spread over two minutes don't add up")
    func slowCallbacksSpreadOverTwoMinutesDontTrip() {
        var sut = armed()
        for second in [0.0, 40, 100, 160] {
            #expect(sut.reduce(.callbackTook(0.2), now: at(second)).isEmpty)
        }
    }

    // MARK: Failing outputs

    @Test("Three failures in a row leave that kind of key to macOS until the output changes")
    func threeFailuresPassThroughClassUntilTargetChanges() {
        var sut = armed()
        for _ in 0..<3 { #expect(press(&sut, .failed(.volume)) == [.pass]) }
        #expect(sut.reduce(down(), now: start) == [.pass])
        _ = sut.reduce(.keyUp(.soundUp), now: start)
        _ = sut.reduce(.targetChanged(.volume), now: start)
        #expect(sut.reduce(down(), now: start) == [.apply(.level(.volume, delta: 1.0 / 16), pending: nil, skipping: [])])
    }

    @Test("A success in between starts the count again")
    func successResetsFailureStreak() {
        var sut = armed()
        press(&sut, .failed(.volume))
        press(&sut, .failed(.volume))
        press(&sut, changed)
        press(&sut, .failed(.volume))
        press(&sut, .failed(.volume))
        #expect(sut.reduce(down(), now: start) == [.apply(.level(.volume, delta: 1.0 / 16), pending: nil, skipping: [])])
    }

    @Test("Volume failing doesn't take brightness with it")
    func failureCountsAreSeparateForEachKind() {
        var sut = armed()
        _ = sut.reduce(.brightnessArmed(true), now: start)
        for _ in 0..<3 { press(&sut, .failed(.volume)) }
        let key = MediaKeyEvent(key: .brightnessUp, phase: .down, isRepeat: false, modifiers: [])
        #expect(sut.reduce(.keyDown(key), now: start) == [.apply(.level(.brightness, delta: 1.0 / 16), pending: nil, skipping: [])])
    }
}
