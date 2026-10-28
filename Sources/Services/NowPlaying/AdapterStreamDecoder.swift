// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Turns the output of `mediaremote-adapter.pl … stream --micros` into
/// snapshots (#10). Each line is `{"type":"data","diff":Bool,"payload":{…}}`.
/// A full payload replaces the state; a diff updates it, with `null` removing
/// a key. Lines may arrive split across reads, so input is buffered to `\n`.
struct AdapterStreamDecoder {
    private var buffer = Data()
    private var state: [String: Any] = [:]

    /// Feeds raw output and returns one entry per complete line that changed
    /// the state: a snapshot, or nil when nothing is playing.
    mutating func feed(_ data: Data) -> [NowPlayingSnapshot?] {
        buffer.append(data)
        var results: [NowPlayingSnapshot?] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty, apply(Data(line)) else { continue }
            results.append(Self.snapshot(from: state))
        }
        return results
    }

    /// Applies one line to the state; false if it wasn't a valid data line.
    private mutating func apply(_ line: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return false }
        if object["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull { state[key] = nil } else { state[key] = value }
            }
        } else {
            state = payload.filter { !($0.value is NSNull) }
        }
        return true
    }

    static func snapshot(from payload: [String: Any]) -> NowPlayingSnapshot? {
        guard let title = (payload["title"] as? String).flatMap(nonEmpty),
              let bundle = (payload["parentApplicationBundleIdentifier"] as? String).flatMap(nonEmpty)
                ?? (payload["bundleIdentifier"] as? String).flatMap(nonEmpty)
        else { return nil }
        let isPlaying = payload["playing"] as? Bool ?? false
        let micros = { (key: String) in (payload[key] as? NSNumber).map { $0.doubleValue / 1_000_000 } }
        let rate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? (isPlaying ? 1 : 0)
        let timestamp = micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) } ?? Date()
        let duration = micros("durationMicros").flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        let artwork = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        let skips = payload["supportsFastForward15Seconds"] as? Bool == true || payload["supportsRewind15Seconds"] as? Bool == true
        let liked = payload["supportsIsLiked"] as? Bool == true ? (payload["isLiked"] as? Bool ?? false) : nil
        return NowPlayingSnapshot(
            title: title,
            artist: (payload["artist"] as? String).flatMap(nonEmpty),
            album: (payload["album"] as? String).flatMap(nonEmpty),
            timeline: PlaybackTimeline(elapsed: micros("elapsedTimeMicros") ?? 0, timestamp: timestamp,
                                       rate: isPlaying ? rate : 0, duration: duration),
            isPlaying: isPlaying,
            sourceBundleID: bundle,
            artwork: artwork,
            supportsSkip15: skips,
            liked: liked
        )
    }

    private static func nonEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
