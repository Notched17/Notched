// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Keep-awake (#38): one power assertion, never leaked.
@Suite("KeepAwakeReducer")
struct KeepAwakeReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 80_000)

    @Test("Starting takes the assertion once and shows the countdown")
    func startAcquiresOnce() {
        var sut = KeepAwakeReducer()
        #expect(sut.reduce(.start(.thirtyMinutes), now: t0) == [.acquire, .post(until: t0 + 1800), .schedule(t0 + 1800)])
        #expect(sut.assertionHeld)
        #expect(sut.mode == .on(until: t0 + 1800))
    }

    @Test("Choosing another preset while on reschedules without a second assertion")
    func presetChangeReschedulesOnly() {
        var sut = KeepAwakeReducer()
        _ = sut.reduce(.start(.thirtyMinutes), now: t0)
        #expect(sut.reduce(.start(.twoHours), now: t0 + 60) == [.post(until: t0 + 60 + 7200), .schedule(t0 + 60 + 7200)])
    }

    @Test("Turning it off releases the assertion and ends the activity")
    func stopReleases() {
        var sut = KeepAwakeReducer()
        _ = sut.reduce(.start(.oneHour), now: t0)
        #expect(sut.reduce(.stop, now: t0 + 10) == [.release, .end, .schedule(nil)])
        #expect(!sut.assertionHeld)
        #expect(sut.mode == .off)
        #expect(sut.reduce(.stop, now: t0 + 11).isEmpty)
    }

    @Test("The time running out releases the assertion")
    func deadlineReleases() {
        var sut = KeepAwakeReducer()
        _ = sut.reduce(.start(.thirtyMinutes), now: t0)
        #expect(sut.reduce(.deadline, now: t0 + 1800) == [.release, .end, .schedule(nil)])
    }

    @Test("Waking after the end releases it; waking before the end reschedules")
    func wakePastEndReleases() {
        var sut = KeepAwakeReducer()
        _ = sut.reduce(.start(.oneHour), now: t0)
        #expect(sut.reduce(.wake, now: t0 + 600) == [.schedule(t0 + 3600)])
        #expect(sut.reduce(.wake, now: t0 + 5000) == [.release, .end, .schedule(nil)])
    }

    @Test("Indefinitely has no deadline")
    func indefiniteHasNoDeadline() {
        var sut = KeepAwakeReducer()
        #expect(sut.reduce(.start(.indefinitely), now: t0) == [.acquire, .post(until: nil), .schedule(nil)])
        #expect(sut.reduce(.deadline, now: t0 + 100_000).isEmpty)
        #expect(sut.reduce(.wake, now: t0 + 100_000).isEmpty)
    }

    @Test("If macOS refuses the assertion, keep-awake turns itself off")
    func acquireFailureTurnsOff() {
        var sut = KeepAwakeReducer()
        _ = sut.reduce(.start(.oneHour), now: t0)
        #expect(sut.reduce(.acquireFailed, now: t0) == [.end, .schedule(nil)])
        #expect(!sut.assertionHeld)
        #expect(sut.mode == .off)
    }

    @Test("Quitting releases the assertion")
    func quitReleases() {
        var sut = KeepAwakeReducer()
        _ = sut.reduce(.start(.indefinitely), now: t0)
        #expect(sut.reduce(.quit, now: t0 + 1) == [.release, .end, .schedule(nil)])
    }

    @Test("Presets are 30 min, 1 h, 2 h and indefinitely")
    func presets() {
        #expect(KeepAwakePreset.allCases.map(\.duration) == [1800, 3600, 7200, nil])
    }

    @Test("Across 1,000 random event sequences, at most one assertion is held and none after quitting")
    func fuzzNeverLeaks() {
        var generator = SeededGenerator(seed: 0x6E6F_7463_6865_64)
        let events: [KeepAwakeReducer.Event] = [
            .start(.thirtyMinutes), .start(.oneHour), .start(.twoHours), .start(.indefinitely),
            .stop, .deadline, .wake, .acquireFailed,
        ]
        for _ in 0..<1_000 {
            var sut = KeepAwakeReducer()
            var held = 0
            var now = t0
            func apply(_ event: KeepAwakeReducer.Event) {
                for effect in sut.reduce(event, now: now) {
                    if effect == .acquire { held += 1 }
                    if effect == .release { held -= 1 }
                }
                if event == .acquireFailed, held > 0 { held -= 1 }
            }
            for _ in 0..<Int.random(in: 1...30, using: &generator) {
                now += Double.random(in: 0...4000, using: &generator)
                // A failure can only follow an acquire the shell just tried.
                var event = events.randomElement(using: &generator)!
                if event == .acquireFailed && !sut.assertionHeld { event = .stop }
                apply(event)
                #expect(held == (sut.assertionHeld ? 1 : 0))
                #expect((0...1).contains(held))
            }
            apply(.quit)
            #expect(held == 0)
            #expect(!sut.assertionHeld)
        }
    }
}

/// A small deterministic generator (SplitMix64), so the fuzz test is repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
