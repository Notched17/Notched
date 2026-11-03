// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The lyric line being sung (#13), under the expanded controls. While
/// playing it redraws only when the line changes (`LyricLineSchedule`), and
/// each new line blurs in.
struct MediaLyricLine: View {
    @Environment(\.islandReduceMotion) private var reduceMotion
    let model: MediaModel

    var body: some View {
        if let snapshot = model.snapshot, let lyrics = model.lyrics {
            if snapshot.isPlaying {
                TimelineView(LyricLineSchedule(lyrics: lyrics, timeline: snapshot.timeline)) { context in
                    line(lyrics, at: snapshot.timeline.elapsed(at: context.date))
                }
            } else {
                line(lyrics, at: snapshot.timeline.elapsed(at: .now))
            }
        }
    }

    private func line(_ lyrics: SyncedLyrics, at time: TimeInterval) -> some View {
        let index = lyrics.lineIndex(at: time)
        let text = index.map { lyrics.lines[$0].text } ?? ""
        return ZStack {
            Text(text.isEmpty ? "♪" : text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .id(index ?? -1)
                .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // Below the island's own transaction override, so line changes animate.
        .animation(reduceMotion ? Motion.reduced : .smooth(duration: 0.35), value: index)
        .accessibilityElement()
        .accessibilityLabel(text.isEmpty ? "Instrumental" : text)
    }
}
