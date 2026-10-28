// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A `TimelineView` schedule with one entry per lyric line change (#13),
/// so the lyric line redraws only when the sung line changes, never on a
/// fixed tick. A seek or a pause posts a new timeline, which rebuilds it.
struct LyricLineSchedule: TimelineSchedule {
    let lyrics: SyncedLyrics
    let timeline: PlaybackTimeline

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(lyrics: lyrics, timeline: timeline, upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let lyrics: SyncedLyrics
        let timeline: PlaybackTimeline
        var upcoming: Date?

        mutating func next() -> Date? {
            guard let date = upcoming else { return nil }
            upcoming = lyrics.nextLineChange(after: date, timeline: timeline)
            return date
        }
    }
}
