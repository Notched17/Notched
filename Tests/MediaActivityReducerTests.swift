// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// When the Now Playing activity is posted, kept or ended (#9). Pins the two
/// bugs found in M2: an ended paused track coming back, and a long-paused
/// session re-elected by macOS showing up as if it had just paused.
@Suite("MediaActivityReducer")
struct MediaActivityReducerTests {
    let lifecycle = MediaLifecycle(staleAfter: 120, endAfter: 600)
    let t0 = Date(timeIntervalSinceReferenceDate: 100_000)

    private func song(_ title: String = "Golden Hour", playing: Bool, updated: Date) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title, artist: "JVKE", album: "SOS",
            timeline: PlaybackTimeline(elapsed: 30, timestamp: updated, rate: playing ? 1 : 0, duration: 209),
            isPlaying: playing, sourceBundleID: "com.apple.Music"
        )
    }

    @Test func playingPostsANewSession() {
        var reducer = MediaActivityReducer()
        #expect(reducer.reduce(song(playing: true, updated: t0), now: t0, lifecycle: lifecycle) == .post(trackChanged: false, isNewSession: true))
        #expect(reducer.reduce(song(playing: true, updated: t0), now: t0 + 5, lifecycle: lifecycle) == .post(trackChanged: false, isNewSession: false))
    }

    @Test func pausingStartsTheClockAtThePause() {
        var reducer = MediaActivityReducer()
        _ = reducer.reduce(song(playing: true, updated: t0), now: t0, lifecycle: lifecycle)
        let paused = t0 + 40
        #expect(reducer.reduce(song(playing: false, updated: paused), now: paused + 1, lifecycle: lifecycle) == .post(trackChanged: false, isNewSession: false))
        #expect(reducer.state.pausedSince == paused)
    }

    @Test func longPausedSessionNeverShows() {
        // The playing app quit and macOS re-elected a tab paused an hour ago.
        var reducer = MediaActivityReducer()
        #expect(reducer.reduce(song(playing: false, updated: t0 - 3600), now: t0, lifecycle: lifecycle) == .none)
        #expect(!reducer.state.isPosted)
    }

    @Test func recentlyPausedSessionShowsForWhatIsLeft() {
        var reducer = MediaActivityReducer()
        #expect(reducer.reduce(song(playing: false, updated: t0 - 60), now: t0, lifecycle: lifecycle) == .post(trackChanged: false, isNewSession: true))
        #expect(lifecycle.endDate(pausedSince: reducer.state.pausedSince) == t0 + 540)
    }

    @Test func endedStaysEnded() {
        var reducer = MediaActivityReducer()
        _ = reducer.reduce(song(playing: false, updated: t0), now: t0, lifecycle: lifecycle)
        #expect(reducer.reduce(song(playing: false, updated: t0), now: t0 + 600, lifecycle: lifecycle) == .end)
        // A later refresh (a setting changed, the app switched) doesn't bring it back.
        #expect(reducer.reduce(song(playing: false, updated: t0), now: t0 + 601, lifecycle: lifecycle) == .none)
    }

    @Test func playingAgainAfterEndingIsANewSession() {
        var reducer = MediaActivityReducer()
        _ = reducer.reduce(song(playing: false, updated: t0), now: t0, lifecycle: lifecycle)
        _ = reducer.reduce(song(playing: false, updated: t0), now: t0 + 600, lifecycle: lifecycle)
        #expect(reducer.reduce(song(playing: true, updated: t0 + 700), now: t0 + 700, lifecycle: lifecycle) == .post(trackChanged: false, isNewSession: true))
    }

    @Test func trackChangeIsReported() {
        var reducer = MediaActivityReducer()
        _ = reducer.reduce(song("One", playing: true, updated: t0), now: t0, lifecycle: lifecycle)
        #expect(reducer.reduce(song("Two", playing: true, updated: t0 + 200), now: t0 + 200, lifecycle: lifecycle) == .post(trackChanged: true, isNewSession: true))
    }

    @Test func nothingPlayingEndsOnce() {
        var reducer = MediaActivityReducer()
        _ = reducer.reduce(song(playing: true, updated: t0), now: t0, lifecycle: lifecycle)
        #expect(reducer.reduce(nil, now: t0 + 1, lifecycle: lifecycle) == .end)
        #expect(reducer.reduce(nil, now: t0 + 2, lifecycle: lifecycle) == .none)
        #expect(reducer.state == MediaActivityReducer.State())
    }
}
