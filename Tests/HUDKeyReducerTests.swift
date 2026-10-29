// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The HUD's decisions about each volume or brightness key press (the safety
/// design §3): when a key goes to macOS, when it is swallowed, and how a
/// press stays paired with its key-up.
@Suite("HUDKeyReducer")
struct HUDKeyReducerTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private static let up = 1.0 / 16
    private static let fine = 1.0 / 64

    private func armed(brightness: Bool = false) -> HUDKeyReducer {
        var sut = HUDKeyReducer()
        for event: HUDKeyReducer.Event in [.armed(true), .visible(true), .trust(true), .brightnessArmed(brightness)] {
            _ = sut.reduce(event, now: now)
        }
        return sut
    }

    private func down(_ key: MediaKeyEvent.Key, _ modifiers: MediaKeyEvent.Modifiers = [],
                      isRepeat: Bool = false) -> HUDKeyReducer.Event {
        .keyDown(MediaKeyEvent(key: key, phase: .down, isRepeat: isRepeat, modifiers: modifiers))
    }

    private func reading(_ level: Double = 0.5625, kind: HUDKind = .volume, atLimit: Bool = false) -> HUDReading {
        HUDReading(kind: kind, targetID: 7, level: level, isMuted: false, atLimit: atLimit)
    }

    private let pending = PendingTarget(kind: .volume, targetID: 7, level: 0.5625)

    private func apply(_ delta: Double = up, pending: PendingTarget? = nil,
                       skipping: Set<UInt32> = []) -> HUDKeyReducer.Effect {
        .apply(.level(.volume, delta: delta), pending: pending, skipping: skipping)
    }

    // MARK: A confirmed press

    @Test("Volume Up applies, and a confirmed change is swallowed and shown")
    func upAppliesThenSwallowsAndShows() {
        var sut = armed()
        #expect(sut.reduce(down(.soundUp), now: now) == [apply()])
        #expect(sut.reduce(.applied(.changed(reading())), now: now) == [.swallow, .show(reading(), modifiers: [])])
    }

    @Test("The mute key applies a toggle")
    func muteKeyAppliesToggle() {
        var sut = armed()
        #expect(sut.reduce(down(.mute), now: now) == [.apply(.toggleMute, pending: nil, skipping: [])])
    }

    @Test("At a limit the key is still swallowed, and the HUD shows it")
    func atLimitSwallows() {
        var sut = armed()
        _ = sut.reduce(down(.soundUp), now: now)
        let limit = reading(1.0, atLimit: true)
        #expect(sut.reduce(.applied(.atLimit(limit)), now: now) == [.swallow, .show(limit, modifiers: [])])
    }

    @Test("An output that can't be adjusted passes the key to macOS")
    func failedApplyPasses() {
        for outcome: ApplyOutcome in [.failed(.volume), .notSettable(.volume), .skipped(.volume)] {
            var sut = armed()
            _ = sut.reduce(down(.soundUp), now: now)
            #expect(sut.reduce(.applied(outcome), now: now) == [.pass])
        }
    }

    // MARK: Passing without trying

    @Test("When the island can't show the HUD, every key goes to macOS untouched")
    func invisibleIslandPassesEveryKey() {
        var sut = armed()
        _ = sut.reduce(.visible(false), now: now)
        #expect(sut.reduce(down(.soundUp), now: now) == [.pass])
        #expect(sut.reduce(.keyUp(.soundUp), now: now) == [.pass])
    }

    @Test("Not armed, or no permission: pass")
    func unarmedOrUntrustedPasses() {
        var fresh = HUDKeyReducer()
        #expect(fresh.reduce(down(.soundUp), now: now) == [.pass])
        var untrusted = armed()
        _ = untrusted.reduce(.trust(false), now: now)
        #expect(untrusted.reduce(down(.soundUp), now: now) == [.pass])
    }

    @Test("Option alone opens Sound settings in macOS, so it passes")
    func optionAlonePasses() {
        var sut = armed()
        #expect(sut.reduce(down(.soundUp, [.option]), now: now) == [.pass])
    }

    @Test("Control and Command aren't ours")
    func controlOrCommandPasses() {
        var sut = armed()
        #expect(sut.reduce(down(.soundUp, [.control]), now: now) == [.pass])
        #expect(sut.reduce(down(.soundUp, [.command]), now: now) == [.pass])
    }

    @Test("Shift+Option is the quarter step")
    func shiftOptionIsFineStep() {
        var sut = armed()
        #expect(sut.reduce(down(.soundUp, [.shift, .option]), now: now) == [apply(Self.fine)])
    }

    @Test("Shift alone is a standard step")
    func shiftIsStandardStep() {
        var sut = armed()
        #expect(sut.reduce(down(.soundDown, [.shift]), now: now) == [apply(-Self.up)])
    }

    @Test("Brightness keys pass until brightness is armed")
    func brightnessPassesWhileUnarmed() {
        var sut = armed(brightness: false)
        #expect(sut.reduce(down(.brightnessUp), now: now) == [.pass])
        var on = armed(brightness: true)
        #expect(on.reduce(down(.brightnessUp), now: now) == [.apply(.level(.brightness, delta: Self.up), pending: nil, skipping: [])])
    }

    // MARK: Pairing

    @Test("The key-up of a fully swallowed press is swallowed")
    func keyUpSwallowedWhenEveryDownWas() {
        var sut = armed()
        _ = sut.reduce(down(.soundUp), now: now)
        _ = sut.reduce(.applied(.changed(reading())), now: now)
        #expect(sut.reduce(.keyUp(.soundUp), now: now) == [.swallow])
    }

    @Test("If macOS saw any down of a press, it gets the key-up too")
    func keyUpPassedWhenAnyDownPassed() {
        var sut = armed()
        _ = sut.reduce(down(.soundUp), now: now)
        _ = sut.reduce(.applied(.changed(reading())), now: now)
        _ = sut.reduce(down(.soundUp, isRepeat: true), now: now)
        _ = sut.reduce(.applied(.failed(.volume)), now: now)
        #expect(sut.reduce(.keyUp(.soundUp), now: now) == [.pass])
    }

    @Test("A key-up from a press we never saw passes")
    func orphanKeyUpPasses() {
        var sut = armed()
        #expect(sut.reduce(.keyUp(.soundUp), now: now) == [.pass])
    }

    @Test("A repeat whose first down we missed passes: macOS already has that press")
    func repeatWithoutFirstDownPasses() {
        var sut = armed()
        #expect(sut.reduce(down(.soundUp, isRepeat: true), now: now) == [.pass])
        #expect(sut.reduce(.keyUp(.soundUp), now: now) == [.pass])
    }

    // MARK: Unconfirmed changes

    @Test("An unconfirmed change is swallowed, asks for a check 150 ms later, and re-applies on it")
    func unconfirmedWakesThenReapplies() {
        var sut = armed()
        _ = sut.reduce(down(.soundUp), now: now)
        let effects = sut.reduce(.applied(.unconfirmed(reading(), pending)), now: now)
        #expect(effects == [.swallow, .show(reading(), modifiers: []), .wake(now.addingTimeInterval(0.15))])
        #expect(sut.reduce(.verifyDue, now: now) == [.reapply(pending)])
    }

    @Test("The next step builds on the pending target")
    func nextStepBuildsOnPending() {
        var sut = armed()
        _ = sut.reduce(down(.soundUp), now: now)
        _ = sut.reduce(.applied(.unconfirmed(reading(), pending)), now: now)
        #expect(sut.reduce(down(.soundUp, isRepeat: true), now: now) == [apply(pending: pending)])
    }

    @Test("Once a check confirms the change, nothing is pending any more")
    func verifiedClearsPending() {
        var sut = armed()
        _ = sut.reduce(down(.soundUp), now: now)
        _ = sut.reduce(.applied(.unconfirmed(reading(), pending)), now: now)
        _ = sut.reduce(.verified(pending, reached: true), now: now)
        _ = sut.reduce(.keyUp(.soundUp), now: now)
        #expect(sut.reduce(down(.soundUp), now: now) == [apply()])
    }

    @Test("Two unconfirmed presses put that output in pass-through; a repeat in the same press counts once")
    func twoUnconfirmedPressesSkipDevice() {
        var sut = armed()
        // Press 1, with a repeat that is also unconfirmed.
        _ = sut.reduce(down(.soundUp), now: now)
        _ = sut.reduce(.applied(.unconfirmed(reading(), pending)), now: now)
        _ = sut.reduce(down(.soundUp, isRepeat: true), now: now)
        _ = sut.reduce(.applied(.unconfirmed(reading(0.625), pending)), now: now)
        _ = sut.reduce(.verified(pending, reached: false), now: now)
        _ = sut.reduce(.keyUp(.soundUp), now: now)
        // Press 2 is still tried: one unconfirmed press isn't enough.
        #expect(sut.reduce(down(.soundUp), now: now) == [apply()])
        _ = sut.reduce(.applied(.unconfirmed(reading(), pending)), now: now)
        _ = sut.reduce(.verified(pending, reached: false), now: now)
        _ = sut.reduce(.keyUp(.soundUp), now: now)
        // Press 3: the output is skipped.
        #expect(sut.reduce(down(.soundUp), now: now) == [apply(skipping: [7])])
        // A new output starts afresh.
        _ = sut.reduce(.applied(.skipped(.volume)), now: now)
        _ = sut.reduce(.keyUp(.soundUp), now: now)
        _ = sut.reduce(.targetChanged(.volume), now: now)
        #expect(sut.reduce(down(.soundUp), now: now) == [apply()])
    }

    @Test("Switching output mid-hold drops the pending target, and the key-up still pairs")
    func outputChangeMidHoldDropsPendingAndPairsKeyUp() {
        var sut = armed()
        _ = sut.reduce(down(.soundUp), now: now)
        _ = sut.reduce(.applied(.unconfirmed(reading(), pending)), now: now)
        _ = sut.reduce(.targetChanged(.volume), now: now)
        #expect(sut.reduce(down(.soundUp, isRepeat: true), now: now) == [apply()])
        _ = sut.reduce(.applied(.changed(reading())), now: now)
        #expect(sut.reduce(.keyUp(.soundUp), now: now) == [.swallow])
    }
}
