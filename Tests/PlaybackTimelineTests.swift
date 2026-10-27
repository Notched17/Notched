// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Elapsed time is interpolated from the last report, never polled (#11).
@Suite("PlaybackTimeline")
struct PlaybackTimelineTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test func interpolatesWhilePlaying() {
        let timeline = PlaybackTimeline(elapsed: 10, timestamp: t0, rate: 1, duration: 200)
        #expect(timeline.elapsed(at: t0.addingTimeInterval(5)) == 15)
    }

    @Test func pausedDoesNotMove() {
        let timeline = PlaybackTimeline(elapsed: 10, timestamp: t0, rate: 0, duration: 200)
        #expect(timeline.elapsed(at: t0.addingTimeInterval(60)) == 10)
    }

    @Test func scalesByRate() {
        let timeline = PlaybackTimeline(elapsed: 10, timestamp: t0, rate: 1.5, duration: 200)
        #expect(timeline.elapsed(at: t0.addingTimeInterval(5)) == 17.5)
    }

    @Test func clampsToDuration() {
        let timeline = PlaybackTimeline(elapsed: 10, timestamp: t0, rate: 1, duration: 12)
        #expect(timeline.elapsed(at: t0.addingTimeInterval(30)) == 12)
        #expect(timeline.remaining(at: t0.addingTimeInterval(30)) == 0)
        let backwards = PlaybackTimeline(elapsed: -3, timestamp: t0, rate: 1, duration: 12)
        #expect(backwards.elapsed(at: t0) == 0)
    }

    @Test func clockBeforeTimestampDoesNotRewind() {
        let timeline = PlaybackTimeline(elapsed: 10, timestamp: t0, rate: 1, duration: 200)
        #expect(timeline.elapsed(at: t0.addingTimeInterval(-2)) == 10)
    }

    @Test func remainingAndFraction() {
        let timeline = PlaybackTimeline(elapsed: 50, timestamp: t0, rate: 1, duration: 200)
        #expect(timeline.remaining(at: t0) == 150)
        #expect(timeline.fraction(at: t0) == 0.25)
    }

    @Test func liveHasNoProgress() {
        let timeline = PlaybackTimeline(elapsed: 50, timestamp: t0, rate: 1, duration: nil)
        #expect(timeline.fraction(at: t0) == nil)
        #expect(timeline.remaining(at: t0) == nil)
        #expect(timeline.elapsed(at: t0.addingTimeInterval(10)) == 60)
    }
}
