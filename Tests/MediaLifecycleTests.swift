// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Paused media goes stale, then ends (#9; defaults 2 and 10 minutes).
@Suite("MediaLifecycle")
struct MediaLifecycleTests {
    let lifecycle = MediaLifecycle(staleAfter: 120, endAfter: 600)
    let paused = Date(timeIntervalSinceReferenceDate: 50_000)

    @Test func playingIsLive() {
        #expect(lifecycle.phase(hasTrack: true, isPlaying: true, pausedSince: nil, now: paused) == .live)
    }

    @Test func pausedUnderStaleIsLive() {
        #expect(lifecycle.phase(hasTrack: true, isPlaying: false, pausedSince: paused, now: paused.addingTimeInterval(119)) == .live)
    }

    @Test func pausedPastStaleIsStale() {
        #expect(lifecycle.phase(hasTrack: true, isPlaying: false, pausedSince: paused, now: paused.addingTimeInterval(120)) == .stale)
    }

    @Test func pausedPastEndIsEnded() {
        #expect(lifecycle.phase(hasTrack: true, isPlaying: false, pausedSince: paused, now: paused.addingTimeInterval(600)) == .ended)
    }

    @Test func nothingPlayingEndsNow() {
        #expect(lifecycle.phase(hasTrack: false, isPlaying: false, pausedSince: nil, now: paused) == .ended)
    }

    @Test func datesFollowPause() {
        #expect(lifecycle.staleDate(pausedSince: paused) == paused.addingTimeInterval(120))
        #expect(lifecycle.endDate(pausedSince: paused) == paused.addingTimeInterval(600))
        #expect(lifecycle.staleDate(pausedSince: nil) == nil)
        #expect(lifecycle.endDate(pausedSince: nil) == nil)
    }

    @Test func endNeverBeforeStale() {
        let odd = MediaLifecycle(staleAfter: 300, endAfter: 60)
        #expect(odd.endDate(pausedSince: paused)! >= odd.staleDate(pausedSince: paused)!)
    }
}
