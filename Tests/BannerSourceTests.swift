// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Turning a stream of states into the banners worth showing (ADR-0012).
@Suite("BannerSource")
struct BannerSourceTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 20_000)

    @Test("The first value seeds the source silently")
    func seedIsSilent() {
        var sut = BannerSource<String>(policy: BannerPolicy(settle: 2))
        #expect(sut.receive("wifi", at: t0) == .none)
        #expect(sut.shown == "wifi")
        #expect(sut.receive("wifi", at: t0 + 1) == .none)
    }

    @Test("With no settle a change is announced at once")
    func zeroSettleEmitsAtOnce() {
        var sut = BannerSource<String>(policy: BannerPolicy())
        sut.seed("battery")
        #expect(sut.receive("charging", at: t0) == .emit("charging"))
        #expect(sut.shown == "charging")
    }

    @Test("A change is announced once it has lasted the settle time")
    func settledChangeEmits() {
        var sut = BannerSource<String>(policy: BannerPolicy(settle: 2))
        sut.seed("wifi")
        #expect(sut.receive("offline", at: t0) == .wake(t0 + 2))
        #expect(sut.advance(to: t0 + 1) == .wake(t0 + 2))
        #expect(sut.advance(to: t0 + 2) == .emit("offline"))
        #expect(sut.advance(to: t0 + 3) == .none)
    }

    @Test("A change that reverts within the settle time says nothing")
    func revertWithinSettleIsSilent() {
        var sut = BannerSource<String>(policy: BannerPolicy(settle: 2))
        sut.seed("wifi")
        _ = sut.receive("offline", at: t0)
        #expect(sut.receive("wifi", at: t0 + 1) == .none)
        #expect(sut.advance(to: t0 + 2) == .none)
        #expect(sut.shown == "wifi")
    }

    @Test("Hearing the pending value again doesn't restart its settle time")
    func repeatedPendingKeepsItsStart() {
        var sut = BannerSource<String>(policy: BannerPolicy(settle: 2))
        sut.seed("wifi")
        _ = sut.receive("offline", at: t0)
        #expect(sut.receive("offline", at: t0 + 1) == .wake(t0 + 2))
    }

    @Test("A different pending value restarts the settle time")
    func newPendingRestarts() {
        var sut = BannerSource<String>(policy: BannerPolicy(settle: 2))
        sut.seed("wifi")
        _ = sut.receive("offline", at: t0)
        #expect(sut.receive("ethernet", at: t0 + 1) == .wake(t0 + 3))
        #expect(sut.advance(to: t0 + 3) == .emit("ethernet"))
    }

    @Test("Within the cooldown the same value isn't announced again (a loose connector)")
    func cooldownSuppressesRepeat() {
        var sut = BannerSource<String>(policy: BannerPolicy(cooldown: 10))
        sut.seed("battery")
        #expect(sut.receive("charging", at: t0) == .emit("charging"))
        #expect(sut.receive("battery", at: t0 + 1) == .emit("battery"))
        #expect(sut.receive("charging", at: t0 + 3) == .none)
        #expect(sut.shown == "charging")
        #expect(sut.receive("battery", at: t0 + 12) == .emit("battery"))
    }

    @Test("Over the rate limit, only the latest state is announced once allowed")
    func rateLimitEmitsOnlyLatestWhenAllowed() {
        var sut = BannerSource<String>(policy: BannerPolicy(maxPerWindow: 2, window: 60))
        sut.seed("a")
        #expect(sut.receive("b", at: t0) == .emit("b"))
        #expect(sut.receive("c", at: t0 + 1) == .emit("c"))
        #expect(sut.receive("d", at: t0 + 2) == .wake(t0 + 60))
        #expect(sut.receive("e", at: t0 + 3) == .wake(t0 + 60))
        #expect(sut.advance(to: t0 + 60) == .emit("e"))
    }

    @Test("Held back by the rate limit and then back where it was: nothing to say")
    func rateLimitedRevertIsSilent() {
        var sut = BannerSource<String>(policy: BannerPolicy(maxPerWindow: 1, window: 60))
        sut.seed("a")
        _ = sut.receive("b", at: t0)
        _ = sut.receive("c", at: t0 + 1)
        #expect(sut.receive("b", at: t0 + 2) == .none)
        #expect(sut.advance(to: t0 + 60) == .none)
    }
}
