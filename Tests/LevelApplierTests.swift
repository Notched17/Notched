// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// A scriptable output: what it reads, whether it can be set, and what the
/// read-back looks like after a set. Records every call.
final class FakeLevelControl: LevelControl, MuteControl, @unchecked Sendable {
    var target: UInt32? = 7
    var settable = true
    /// What `level(_:)` reads; nil is a failed read.
    var levelValue: Double? = 0.5
    var setSucceeds = true
    /// The value the device reports after a set: (requested, previous) -> new.
    var afterSet: (Double, Double?) -> Double? = { requested, _ in requested }
    var muted: Bool? = false
    var muteSetSucceeds = true
    var muteApplies = true

    private(set) var setCalls: [Double] = []
    private(set) var muteCalls: [Bool] = []
    private(set) var readCount = 0

    func currentTarget() -> UInt32? { target }
    func isSettable(_ id: UInt32) -> Bool { settable }
    func level(_ id: UInt32) -> Double? {
        readCount += 1
        return levelValue
    }
    func setLevel(_ value: Double, on id: UInt32) -> Bool {
        setCalls.append(value)
        guard setSucceeds else { return false }
        levelValue = afterSet(value, levelValue)
        return true
    }
    func isMuted(_ id: UInt32) -> Bool? { muted }
    func setMuted(_ newValue: Bool, on id: UInt32) -> Bool {
        muteCalls.append(newValue)
        guard muteSetSucceeds else { return false }
        if muteApplies { muted = newValue }
        return true
    }
}

@Suite("LevelApplier")
struct LevelApplierTests {
    private static let up = 1.0 / 16
    private static let down = -1.0 / 16

    private func volume(_ fake: FakeLevelControl, _ delta: Double = up,
                        pending: PendingTarget? = nil, skipping: Set<UInt32> = []) -> ApplyOutcome {
        LevelApplier.apply(.level(.volume, delta: delta), pending: pending, skipping: skipping, levels: fake, mute: fake)
    }

    private func reading(_ level: Double, muted: Bool = false, atLimit: Bool = false, kind: HUDKind = .volume) -> HUDReading {
        HUDReading(kind: kind, targetID: 7, level: level, isMuted: muted, atLimit: atLimit)
    }

    // MARK: Targets

    @Test("Targets land on the 1/16 grid, and the fine step on 1/64")
    func targetRoundsToGrid() {
        #expect(LevelApplier.target(current: 0.5, pending: nil, delta: 1.0 / 16) == 0.5625)
        #expect(LevelApplier.target(current: 0.53, pending: nil, delta: 1.0 / 16) == 0.5625)
        #expect(LevelApplier.target(current: 0.5, pending: nil, delta: 1.0 / 64) == 0.515625)
        #expect(LevelApplier.target(current: 0.97, pending: nil, delta: 1.0 / 16) == 1.0)
        #expect(LevelApplier.target(current: 0.03, pending: nil, delta: -1.0 / 16) == 0.0)
    }

    @Test("A pending target is built on, not the stale read")
    func targetBuildsOnPending() {
        #expect(LevelApplier.target(current: 0.5, pending: 0.5625, delta: 1.0 / 16) == 0.625)
    }

    // MARK: Changes

    @Test("A change whose read-back reaches the target is confirmed")
    func changedWhenReadbackReachesTarget() {
        let fake = FakeLevelControl()
        #expect(volume(fake) == .changed(reading(0.5625)))
        #expect(fake.setCalls == [0.5625])
    }

    @Test("Hardware that rounds the value still counts when it moved the right way")
    func roundingHardwareCountsAsChanged() {
        let fake = FakeLevelControl()
        fake.afterSet = { _, _ in 0.55 }
        #expect(volume(fake) == .changed(reading(0.5625)))
    }

    @Test("A read-back that hasn't moved is unconfirmed, with the target kept")
    func staleReadbackIsUnconfirmed() {
        let fake = FakeLevelControl()
        fake.afterSet = { _, previous in previous }
        let pending = PendingTarget(kind: .volume, targetID: 7, level: 0.5625)
        #expect(volume(fake) == .unconfirmed(reading(0.5625), pending))
    }

    @Test("A read-back that can't be read is unconfirmed too, never passed")
    func unreadableReadbackIsUnconfirmed() {
        let fake = FakeLevelControl()
        fake.afterSet = { _, _ in nil }
        let pending = PendingTarget(kind: .volume, targetID: 7, level: 0.5625)
        #expect(volume(fake) == .unconfirmed(reading(0.5625), pending))
    }

    @Test("A property that can't be set passes the key, and nothing is written")
    func notSettablePasses() {
        let fake = FakeLevelControl()
        fake.settable = false
        #expect(volume(fake) == .notSettable(.volume))
        #expect(fake.setCalls.isEmpty)
    }

    @Test("A failed set passes the key")
    func setFailureIsFailed() {
        let fake = FakeLevelControl()
        fake.setSucceeds = false
        #expect(volume(fake) == .failed(.volume))
    }

    @Test("No output to adjust passes the key")
    func noTargetIsFailed() {
        let fake = FakeLevelControl()
        fake.target = nil
        #expect(volume(fake) == .failed(.volume))
    }

    @Test("A failed read passes the key")
    func unreadableLevelIsFailed() {
        let fake = FakeLevelControl()
        fake.levelValue = nil
        #expect(volume(fake) == .failed(.volume))
    }

    @Test("Brightness takes no mute control")
    func brightnessNeedsNoMute() {
        let fake = FakeLevelControl()
        let outcome = LevelApplier.apply(.level(.brightness, delta: Self.up), pending: nil, skipping: [],
                                         levels: fake, mute: nil)
        #expect(outcome == .changed(reading(0.5625, kind: .brightness)))
        #expect(fake.muteCalls.isEmpty)
    }

    // MARK: The limits

    @Test("Up at the top is a limit: nothing is written, the output isn't touched")
    func upAtMaxIsAtLimit() {
        let fake = FakeLevelControl()
        fake.levelValue = 1.0
        #expect(volume(fake) == .atLimit(reading(1.0, atLimit: true)))
        #expect(fake.setCalls.isEmpty)
        #expect(fake.muteCalls.isEmpty)
    }

    @Test("Down at the bottom is a limit and makes sure the output is muted")
    func downAtZeroIsAtLimitAndMutes() {
        let fake = FakeLevelControl()
        fake.levelValue = 0.0
        #expect(volume(fake, Self.down) == .atLimit(reading(0.0, muted: true, atLimit: true)))
        #expect(fake.setCalls.isEmpty)
        #expect(fake.muteCalls == [true])
    }

    // MARK: Mute

    @Test("Raising the volume while muted unmutes")
    func raisingFromMuteUnmutes() {
        let fake = FakeLevelControl()
        fake.muted = true
        #expect(volume(fake) == .changed(reading(0.5625, muted: false)))
        #expect(fake.muteCalls == [false])
    }

    @Test("Reaching zero mutes, as macOS does")
    func reachingZeroMutes() {
        let fake = FakeLevelControl()
        fake.levelValue = 0.0625
        #expect(volume(fake, Self.down) == .changed(reading(0.0, muted: true)))
        #expect(fake.setCalls == [0.0])
        #expect(fake.muteCalls == [true])
    }

    @Test("The mute key flips mute and confirms it by reading it back")
    func toggleMuteConfirmed() {
        let fake = FakeLevelControl()
        let outcome = LevelApplier.apply(.toggleMute, pending: nil, skipping: [], levels: fake, mute: fake)
        #expect(outcome == .changed(reading(0.5, muted: true)))
        #expect(fake.muteCalls == [true])
    }

    @Test("A mute that doesn't show in the read-back passes the key")
    func toggleMuteReadbackUnchangedFails() {
        let fake = FakeLevelControl()
        fake.muteApplies = false
        let outcome = LevelApplier.apply(.toggleMute, pending: nil, skipping: [], levels: fake, mute: fake)
        #expect(outcome == .failed(.volume))
    }

    // MARK: Devices

    @Test("An output in pass-through is left alone: nothing is read or written")
    func skippedDevice() {
        let fake = FakeLevelControl()
        #expect(volume(fake, skipping: [7]) == .skipped(.volume))
        #expect(fake.readCount == 0)
        #expect(fake.setCalls.isEmpty)
    }

    @Test("A pending target for another output is ignored")
    func pendingForOtherDeviceIgnored() {
        let fake = FakeLevelControl()
        let stale = PendingTarget(kind: .volume, targetID: 3, level: 0.9)
        #expect(volume(fake, pending: stale) == .changed(reading(0.5625)))
    }

    @Test("A matching pending target is built on")
    func pendingForSameDeviceIsUsed() {
        let fake = FakeLevelControl()
        let pending = PendingTarget(kind: .volume, targetID: 7, level: 0.5625)
        #expect(volume(fake, pending: pending) == .changed(reading(0.625)))
    }

    // MARK: Re-applying an unconfirmed change

    @Test("Re-applying sets the pending target once more and reports whether it took")
    func reapplyReportsWhetherItTook() {
        let fake = FakeLevelControl()
        let pending = PendingTarget(kind: .volume, targetID: 7, level: 0.5625)
        #expect(LevelApplier.reapply(pending, levels: fake) == true)
        #expect(fake.setCalls == [0.5625])
        fake.levelValue = 0.5
        fake.afterSet = { _, previous in previous }
        #expect(LevelApplier.reapply(pending, levels: fake) == false)
    }

    @Test("Re-applying never touches a different output")
    func reapplyIgnoresOtherDevice() {
        let fake = FakeLevelControl()
        fake.target = 9
        let pending = PendingTarget(kind: .volume, targetID: 7, level: 0.5625)
        #expect(LevelApplier.reapply(pending, levels: fake) == false)
        #expect(fake.setCalls.isEmpty)
    }
}
