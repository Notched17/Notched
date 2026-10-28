// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Time-synced lyrics: lines in time order (#13).
struct SyncedLyrics: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        /// Seconds from the start of the track.
        var time: TimeInterval
        /// Empty for an instrumental break.
        var text: String
    }

    var lines: [Line]

    /// The line being sung at `time`: the last one that has started, or nil
    /// before the first. Binary search, since this runs on every redraw.
    func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= time { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}

/// Parses LRC (`[mm:ss.xx]text`), the format LRCLIB's `syncedLyrics` uses.
/// Metadata tags are skipped, except `[offset:±ms]`, which shifts every line
/// (a positive offset shows lyrics earlier). Lines with several timestamps
/// (a repeated chorus) appear once per timestamp.
enum LRCParser {
    static func parse(_ text: String) -> SyncedLyrics {
        var offset: TimeInterval = 0
        var lines: [SyncedLyrics.Line] = []
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            var rest = Substring(rawLine)
            var times: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let time = timestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"), let milliseconds = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = milliseconds / 1000
                }
            }
            let words = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            lines += times.map { SyncedLyrics.Line(time: $0, text: words) }
        }
        let shifted = lines.map { SyncedLyrics.Line(time: max($0.time - offset, 0), text: $0.text) }
        // A stable sort keeps lines with the same time in their written order.
        let sorted = shifted.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
        return SyncedLyrics(lines: sorted)
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`.
    private static func timestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Int(parts[0]), minutes >= 0,
              let seconds = Double(parts[1]), seconds >= 0, seconds < 60,
              parts[1].first?.isNumber == true else { return nil }
        return Double(minutes) * 60 + seconds
    }
}
