// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Feeds synthetic key events into the real engine, standing in for the
/// event tap, and records the verdict for each and everything delivered to
/// the main side.
final class FakeTapHost: @unchecked Sendable {
    let engine: HUDKeyEngine
    private let lock = NSLock()
    private var recorded: [HUDKeyReducer.Effect] = []

    var delivered: [HUDKeyReducer.Effect] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init(volume: some LevelControl & MuteControl, brightness: (any LevelControl)? = nil, armed: Bool = true) {
        let box = Box()
        engine = HUDKeyEngine(volume: volume, brightness: brightness, now: { Date(timeIntervalSince1970: 1_000) },
                              deliver: { box.host?.record($0) })
        box.host = self
        if armed {
            engine.send(.armed(true))
            engine.send(.visible(true))
            engine.send(.trust(true))
        }
    }

    private final class Box: @unchecked Sendable { weak var host: FakeTapHost? }

    fileprivate func record(_ effects: [HUDKeyReducer.Effect]) {
        lock.lock()
        recorded.append(contentsOf: effects)
        lock.unlock()
    }

    /// A key going down, `repeats` auto-repeats, then up. The verdict of each.
    @discardableResult
    func press(_ key: MediaKeyEvent.Key, _ modifiers: MediaKeyEvent.Modifiers = [], repeats: Int = 0) -> [TapVerdict] {
        var verdicts = [engine.handle(MediaKeyEvent(key: key, phase: .down, isRepeat: false, modifiers: modifiers))]
        for _ in 0..<repeats {
            verdicts.append(engine.handle(MediaKeyEvent(key: key, phase: .down, isRepeat: true, modifiers: modifiers)))
        }
        verdicts.append(engine.handle(MediaKeyEvent(key: key, phase: .up, isRepeat: false, modifiers: modifiers)))
        return verdicts
    }
}

@Suite("HUDKeyEngine")
struct HUDKeyEngineTests {
    @Test("A confirmed press is swallowed, down and up, and shown once")
    func confirmedPressIsSwallowedEndToEnd() {
        let fake = FakeLevelControl()
        let host = FakeTapHost(volume: fake)
        #expect(host.press(.soundUp) == [.swallow, .swallow])
        #expect(fake.setCalls == [0.5625])
        let shows = host.delivered.filter { if case .show = $0 { true } else { false } }
        #expect(shows == [.show(HUDReading(kind: .volume, targetID: 7, level: 0.5625, isMuted: false, atLimit: false), modifiers: [])])
    }

    @Test("A control that fails passes both halves of the press, and shows nothing")
    func failingControlPassesEndToEnd() {
        let fake = FakeLevelControl()
        fake.setSucceeds = false
        let host = FakeTapHost(volume: fake)
        #expect(host.press(.soundUp) == [.pass, .pass])
        #expect(host.delivered.isEmpty)
    }

    @Test("Holding the key at the top stays on our HUD for the whole hold")
    func holdAtMaxStaysOnOurHUD() {
        let fake = FakeLevelControl()
        fake.levelValue = 1.0
        let host = FakeTapHost(volume: fake)
        let verdicts = host.press(.soundUp, repeats: 5)
        #expect(verdicts.count == 7)
        #expect(verdicts.allSatisfy { $0 == .swallow })
        #expect(fake.setCalls.isEmpty)
    }

    @Test("Disarming takes effect on the very next key")
    func pauseFlipsBeforeTeardown() {
        let host = FakeTapHost(volume: FakeLevelControl())
        host.engine.send(.armed(false))
        #expect(host.press(.soundUp) == [.pass, .pass])
    }

    @Test("A second timeout hands back a removal, and delivers the latch")
    func secondTimeoutReturnsRemove() {
        let host = FakeTapHost(volume: FakeLevelControl())
        #expect(host.engine.tapDisabled(byTimeout: true, trusted: true) == .reEnable)
        #expect(host.engine.tapDisabled(byTimeout: true, trusted: true) == .remove(.timeouts))
        #expect(host.delivered.contains(.latch(.timeouts)))
    }

    @Test("Losing the permission hands back a removal without a latch")
    func permissionLossReturnsRemove() {
        let host = FakeTapHost(volume: FakeLevelControl())
        #expect(host.engine.tapDisabled(byTimeout: true, trusted: false) == .remove(.permissionRevoked))
        #expect(!host.delivered.contains(.latch(.permissionRevoked)))
    }

    @Test("Slow callbacks are reported to the reducer")
    func slowCallbacksTrip() {
        let host = FakeTapHost(volume: FakeLevelControl())
        #expect(host.engine.callbackTook(0.2) == .none)
        #expect(host.engine.callbackTook(0.2) == .none)
        #expect(host.engine.callbackTook(0.2) == .remove(.slowCallbacks))
    }

    @Test("The output is adjusted outside the lock, so it may call back into the engine", .timeLimit(.minutes(1)))
    func applyRunsOutsideLock() {
        let fake = FakeLevelControl()
        let host = FakeTapHost(volume: fake)
        fake.onSet = { [engine = host.engine] in engine.send(.visible(true)) }
        #expect(host.press(.soundUp) == [.swallow, .swallow])
    }

    @Test("The engine works off the main thread, as the tap does")
    func engineWorksOffMain() async {
        let host = FakeTapHost(volume: FakeLevelControl())
        let verdict = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: host.engine.handle(MediaKeyEvent(key: .soundUp, phase: .down, isRepeat: false, modifiers: [])))
            }
        }
        #expect(verdict == .swallow)
    }

    @Test("A change the output hadn't reported is set again when the check comes due")
    func verifyReappliesUnconfirmedChange() {
        let fake = FakeLevelControl()
        fake.afterSet = { _, previous in previous }
        let host = FakeTapHost(volume: fake)
        #expect(host.press(.soundUp) == [.swallow, .swallow])
        #expect(host.delivered.contains(.wake(Date(timeIntervalSince1970: 1_000.15))))
        fake.afterSet = { requested, _ in requested }
        host.engine.send(.verifyDue)
        #expect(fake.setCalls == [0.5625, 0.5625])
        // Now confirmed, so the next press starts from what the output reports.
        fake.levelValue = 0.5625
        #expect(host.press(.soundUp) == [.swallow, .swallow])
        #expect(fake.setCalls.last == 0.625)
    }

    @Test("Brightness keys go to the display control when there is one, and to macOS when not")
    func brightnessUsesItsOwnControl() {
        let display = FakeLevelControl()
        display.target = 1
        let withDisplay = FakeTapHost(volume: FakeLevelControl(), brightness: display)
        withDisplay.engine.send(.brightnessArmed(true))
        #expect(withDisplay.press(.brightnessUp) == [.swallow, .swallow])
        #expect(display.setCalls == [0.5625])

        let without = FakeTapHost(volume: FakeLevelControl(), brightness: nil)
        without.engine.send(.brightnessArmed(true))
        #expect(without.press(.brightnessUp) == [.pass, .pass])
    }
}
