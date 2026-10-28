// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Decides, for each Now Playing update, whether the activity is posted,
/// kept or ended (#9). Pure, so the paused lifecycle is tested.
///
/// - A pause is timed from when the player says it paused (its last
///   position report), not from when Notched first saw it. A session macOS
///   re-elects after the playing app quits, paused an hour ago, never shows.
/// - Once ended for pausing too long, a track stays off the island until it
///   plays again or another track replaces it.
struct MediaActivityReducer: Equatable {
    struct State: Equatable {
        var pausedSince: Date?
        var lastTrack: TrackKey?
        var isPosted = false
    }

    enum Action: Equatable {
        /// Leave the island as it is.
        case none
        /// Post (or update) the activity. A new session (first post, or a new
        /// track) reloads per-track data such as lyrics and the favourite.
        case post(trackChanged: Bool, isNewSession: Bool)
        /// Take the activity off the island.
        case end
    }

    private(set) var state = State()

    mutating func reduce(_ snapshot: NowPlayingSnapshot?, now: Date, lifecycle: MediaLifecycle) -> Action {
        guard let snapshot else {
            let wasPosted = state.isPosted
            state = State()
            return wasPosted ? .end : .none
        }
        let isNewTrack = snapshot.trackKey != state.lastTrack
        if snapshot.isPlaying {
            state.pausedSince = nil
        } else if state.pausedSince == nil || isNewTrack {
            state.pausedSince = min(now, snapshot.timeline.timestamp)
        }
        let phase = lifecycle.phase(hasTrack: true, isPlaying: snapshot.isPlaying, pausedSince: state.pausedSince, now: now)
        guard phase != .ended else {
            state.lastTrack = snapshot.trackKey
            let wasPosted = state.isPosted
            state.isPosted = false
            return wasPosted ? .end : .none
        }
        let trackChanged = state.lastTrack != nil && isNewTrack
        let isNewSession = isNewTrack || !state.isPosted
        state.lastTrack = snapshot.trackKey
        state.isPosted = true
        return .post(trackChanged: trackChanged, isNewSession: isNewSession)
    }
}
