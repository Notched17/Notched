// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The lyric line being sung (#13), under the expanded controls or, as a
/// ticker, beside the notch. It follows the interpolated playback position
/// twice a second while playing, and each new line blurs in.
struct MediaLyricLine: View {
    let model: MediaModel
    var compact = false

    var body: some View {
        if let snapshot = model.snapshot, let lyrics = model.lyrics {
            if snapshot.isPlaying {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
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
                .font(compact ? IslandFont.minimal : .system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(compact ? AnyShapeStyle(model.tint) : AnyShapeStyle(.white.opacity(0.9)))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(compact ? 1 : 0.85)
                .id(index ?? -1)
                .transition(AnyTransition(.blurReplace).combined(with: .opacity))
        }
        .frame(maxWidth: compact ? IslandMetrics.compactRegionMaxWidth : .infinity, alignment: compact ? .leading : .center)
        // Below the island's own transaction override, so line changes animate.
        .animation(.smooth(duration: 0.35), value: index)
        .accessibilityElement()
        .accessibilityLabel(text.isEmpty ? "Instrumental" : text)
    }
}
