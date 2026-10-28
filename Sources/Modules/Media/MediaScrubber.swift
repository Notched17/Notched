// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The seek bar (#11), in the style of Apple Music: elapsed time, a thin bar
/// that thickens under the pointer, and the time remaining. Dragging
/// previews the new position in the time labels and seeks on release.
///
/// The position is worked out from the timeline. It redraws twice a second,
/// and only while the island is expanded and the media is playing.
struct MediaScrubber: View {
    let timeline: PlaybackTimeline
    var tint: Color = .white
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var isHovering = false
    @State private var lastSeek: (fraction: Double, at: Date)?

    var body: some View {
        if timeline.duration == nil {
            liveBadge
        } else if timeline.rate != 0 && dragFraction == nil {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                bar(at: context.date)
            }
        } else {
            bar(at: .now)
        }
    }

    private func bar(at date: Date) -> some View {
        let duration = timeline.duration ?? 0
        let fraction = dragFraction ?? displayedFraction(at: date)
        let elapsed = fraction * duration
        let active = isHovering || dragFraction != nil
        return HStack(spacing: Spacing.s) {
            Text(Self.format(elapsed))
                .frame(minWidth: 34, alignment: .leading)
            GeometryReader { proxy in
                let height: CGFloat = active ? 8 : 5
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(tint.opacity(active ? 1 : 0.85))
                        .frame(width: max(height, proxy.size.width * fraction))
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                    }
                    .onEnded { value in
                        let target = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        dragFraction = nil
                        lastSeek = (target, Date())
                        if let time = timeline.time(forFraction: target) { onSeek(time) }
                    })
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
            }
            .frame(height: 16)
            .onHover { isHovering = $0 }
            Text("−" + Self.format(max(duration - elapsed, 0)))
                .frame(minWidth: 40, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.format(elapsed)) of \(Self.format(duration))")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 15.0 : -15.0
            onSeek(min(max(elapsed + step, 0), duration))
        }
    }

    /// Right after a seek, keep showing the target until the player
    /// reports the new position, so the bar doesn't jump back.
    private func displayedFraction(at date: Date) -> Double {
        if let lastSeek, date.timeIntervalSince(lastSeek.at) < 1.5, timeline.timestamp < lastSeek.at {
            return lastSeek.fraction
        }
        return timeline.fraction(at: date) ?? 0
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("LIVE").font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 16)
        .accessibilityLabel("Live")
    }

    /// m:ss, or h:mm:ss past an hour.
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
