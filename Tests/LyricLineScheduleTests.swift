// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The lyric line redraws only when the sung line changes, instead of
/// twice a second (M2 review).
@Suite("Lyric line schedule")
struct LyricLineScheduleTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    let lyrics = SyncedLyrics(lines: [
        .init(time: 5, text: "one"), .init(time: 12, text: "two"), .init(time: 20, text: "three"),
    ])

    private func timeline(elapsed: TimeInterval = 10, rate: Double = 1, duration: TimeInterval? = 200) -> PlaybackTimeline {
        PlaybackTimeline(elapsed: elapsed, timestamp: t0, rate: rate, duration: duration)
    }

    @Test("At normal speed the next change is when the next line starts")
    func nextChangeAtRateOne() throws {
        let next = try #require(lyrics.nextLineChange(after: t0, timeline: timeline()))
        #expect(abs(next.timeIntervalSince(t0) - (2 + SyncedLyrics.lineChangeGuard)) < 0.0001)
    }

    @Test("Paused playback never changes line")
    func pausedHasNoNextChange() {
        #expect(lyrics.nextLineChange(after: t0, timeline: timeline(rate: 0)) == nil)
    }

    @Test("After the last line nothing changes")
    func pastLastLineHasNone() {
        #expect(lyrics.nextLineChange(after: t0, timeline: timeline(elapsed: 25)) == nil)
    }

    @Test("Before the first line, the first line is next")
    func beforeFirstLine() throws {
        let next = try #require(lyrics.nextLineChange(after: t0, timeline: timeline(elapsed: 1)))
        #expect(abs(next.timeIntervalSince(t0) - (4 + SyncedLyrics.lineChangeGuard)) < 0.0001)
    }

    @Test("Faster playback (a podcast at 2×) halves the wait")
    func doubleRateHalvesWait() throws {
        let next = try #require(lyrics.nextLineChange(after: t0, timeline: timeline(rate: 2)))
        #expect(abs(next.timeIntervalSince(t0) - (1 + SyncedLyrics.lineChangeGuard)) < 0.0001)
    }

    @Test("A line past the track's end never comes")
    func lineAfterDurationIgnored() {
        #expect(lyrics.nextLineChange(after: t0, timeline: timeline(duration: 11)) == nil)
    }

    @Test("At the returned moment the next line is the one showing")
    func lineIndexAtReturnedDateIsTheNextLine() throws {
        let timeline = timeline()
        var date = t0
        for expected in [1, 2] {
            date = try #require(lyrics.nextLineChange(after: date, timeline: timeline))
            #expect(lyrics.lineIndex(at: timeline.elapsed(at: date)) == expected)
        }
        #expect(lyrics.nextLineChange(after: date, timeline: timeline) == nil)
    }
}
