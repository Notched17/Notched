// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How long paused media stays on the island (#9). It dims ("stale") after
/// `staleAfter`, and leaves the island after `endAfter`. Nothing playing at
/// all ends it straight away.
struct MediaLifecycle: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case live, stale, ended
    }

    /// Seconds paused before the activity looks stale (default 2 min).
    var staleAfter: TimeInterval
    /// Seconds paused before the activity ends (default 10 min).
    var endAfter: TimeInterval

    func phase(hasTrack: Bool, isPlaying: Bool, pausedSince: Date?, now: Date) -> Phase {
        guard hasTrack else { return .ended }
        guard !isPlaying, let pausedSince else { return .live }
        if let end = endDate(pausedSince: pausedSince), now >= end { return .ended }
        if let stale = staleDate(pausedSince: pausedSince), now >= stale { return .stale }
        return .live
    }

    func staleDate(pausedSince: Date?) -> Date? {
        pausedSince?.addingTimeInterval(staleAfter)
    }

    /// Never before the stale date, even if the settings say otherwise.
    func endDate(pausedSince: Date?) -> Date? {
        pausedSince?.addingTimeInterval(max(endAfter, staleAfter))
    }
}
