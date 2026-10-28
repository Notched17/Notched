// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where playback is, as last reported. The elapsed time is worked out from
/// the report whenever it's needed, never polled from the player (#11).
struct PlaybackTimeline: Equatable, Sendable {
    /// Seconds into the track at `timestamp`.
    var elapsed: TimeInterval
    var timestamp: Date
    /// 0 while paused, 1 at normal speed (1.5 for a podcast played faster).
    var rate: Double
    /// Nil for live streams and radio.
    var duration: TimeInterval?

    func elapsed(at date: Date) -> TimeInterval {
        let moved = elapsed + max(date.timeIntervalSince(timestamp), 0) * rate
        return min(max(moved, 0), duration ?? .infinity)
    }

    func remaining(at date: Date) -> TimeInterval? {
        duration.map { max($0 - elapsed(at: date), 0) }
    }

    /// 0…1 through the track, or nil when it has no length.
    func fraction(at date: Date) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return elapsed(at: date) / duration
    }

    /// The time at a point on the seek bar (0…1, clamped); nil for live streams.
    func time(forFraction fraction: Double) -> TimeInterval? {
        guard let duration, duration > 0 else { return nil }
        return min(max(fraction, 0), 1) * duration
    }
}

/// Identifies a track across play/pause updates. MediaRemote's content item
/// identifier changes on every play and pause, so it can't be used.
struct TrackKey: Hashable, Sendable {
    var title: String
    var artist: String
    var album: String
}

/// What's playing, from whichever backend is active.
struct NowPlayingSnapshot: Equatable, Sendable {
    var title: String
    var artist: String?
    var album: String?
    var timeline: PlaybackTimeline
    var isPlaying: Bool
    /// The app playing it (for web media, the browser rather than its helper process).
    var sourceBundleID: String
    /// Encoded image data (JPEG/PNG) as the player provides it.
    var artwork: Data?
    /// The source supports ±15 s skips (podcasts, audiobooks).
    var supportsSkip15: Bool = false
    /// Whether the track is liked, when the source says.
    var liked: Bool?

    var trackKey: TrackKey { TrackKey(title: title, artist: artist ?? "", album: album ?? "") }
}

/// A transport command for the source app.
enum MediaCommand: Equatable, Sendable {
    case play, pause, togglePlayPause, next, previous
    case skipForward15, skipBackward15
    /// Seconds from the start of the track.
    case seek(TimeInterval)
}
