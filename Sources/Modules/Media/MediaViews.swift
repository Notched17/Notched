// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// The Now Playing regions (#9). The reference is the Music Live Activity in
// the iPhone Dynamic Island: artwork leading, a live waveform trailing,
// title and artist under the camera, then the scrubber and the transport
// controls with AirPlay at the end of the row.

/// Album artwork in a continuous-corner square (or a circle in a bubble).
/// A new track blurs in; missing artwork shows a quiet note glyph.
struct MediaArtworkView: View {
    let model: MediaModel
    var size: CGFloat
    var circular = false

    var body: some View {
        ZStack {
            Group {
                if let artwork = model.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Rectangle().fill(.white.opacity(0.14))
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.46, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .id(ArtworkIdentity(track: model.trackKey, hasArtwork: model.artwork != nil))
            .transition(AnyTransition(.blurReplace).combined(with: .opacity))
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: circular ? size / 2 : size * 0.23, style: .continuous)
    }
}

private struct ArtworkIdentity: Hashable {
    var track: TrackKey?
    var hasArtwork: Bool
}

/// The waveform beside the notch, tinted with the artwork's colour.
struct MediaBarsView: View {
    let model: MediaModel
    var height: CGFloat
    var barCount = 4
    var barWidth: CGFloat = 2.5

    var body: some View {
        MediaVisualizer(
            isPlaying: model.isPlaying,
            tint: model.tintRGB,
            barCount: barCount,
            barWidth: barWidth,
            height: height,
            style: model.visualizer
        )
        .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barWidth * 0.9, height: height)
    }
}

/// A bubble: the waveform while playing; the artwork while paused, when
/// still bars would say nothing.
struct MediaMinimalView: View {
    let model: MediaModel

    var body: some View {
        if model.isPlaying && model.visualizer != .off {
            MediaBarsView(model: model, height: 12, barWidth: 2)
        } else {
            MediaArtworkView(model: model, size: 20, circular: true)
        }
    }
}

/// Title, then artist with the source app's icon, under the camera housing.
struct MediaTitleBlock: View {
    let model: MediaModel

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot?.title ?? "")
                .font(IslandFont.title)
                .lineLimit(1)
            HStack(spacing: 5) {
                if let icon = model.sourceIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }
                Text(snapshot?.artist ?? model.sourceName ?? "")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Scrubber, transport controls and (later) the current lyric line.
struct MediaExpandedBottom: View {
    let model: MediaModel

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if let snapshot = model.snapshot {
                MediaScrubber(timeline: snapshot.timeline, tint: .white) { model.actions.send(.seek($0)) }
            }
            MediaControlsRow(model: model)
            if model.lyrics != nil {
                MediaLyricLine(model: model)
                    .padding(.top, Spacing.xxs)
            }
        }
    }
}

/// [♥]  ⏮ ⏯ ⏭  [output]. Podcasts and long content add ±15 s.
struct MediaControlsRow: View {
    let model: MediaModel

    var body: some View {
        let skips = model.snapshot.map(MediaControlsRow.showsSkip) ?? false
        HStack(spacing: 0) {
            Group {
                if let liked = model.liked, model.canLike {
                    MediaControlButton(symbol: liked ? "heart.fill" : "heart", label: liked ? "Unfavourite" : "Favourite",
                                       size: 15, tint: liked ? .pink : .white.opacity(0.85)) { model.actions.toggleLike() }
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.accessoryWidth, height: 30)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.m) {
                if skips, let snapshot = model.snapshot {
                    MediaControlButton(symbol: "gobackward.15", label: "Back 15 Seconds", size: 17) {
                        model.actions.send(Self.skipCommand(forward: false, snapshot: snapshot, at: .now))
                    }
                }
                MediaControlButton(symbol: "backward.fill", label: "Previous", size: 18) { model.actions.send(.previous) }
                MediaControlButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", label: model.isPlaying ? "Pause" : "Play",
                                   size: 24) { model.actions.send(.togglePlayPause) }
                MediaControlButton(symbol: "forward.fill", label: "Next", size: 18) { model.actions.send(.next) }
                if skips, let snapshot = model.snapshot {
                    MediaControlButton(symbol: "goforward.15", label: "Forward 15 Seconds", size: 17) {
                        model.actions.send(Self.skipCommand(forward: true, snapshot: snapshot, at: .now))
                    }
                }
            }
            Spacer(minLength: 0)
            Group {
                if let outputs = model.outputs, outputs.current != nil {
                    MediaOutputButton(outputs: outputs)
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.accessoryWidth, height: 30)
        }
    }

    static let accessoryWidth: CGFloat = 30

    /// ±15 s when the source says it supports it, or for long content
    /// (podcast episodes, audiobooks, long videos).
    nonisolated static func showsSkip(_ snapshot: NowPlayingSnapshot) -> Bool {
        snapshot.supportsSkip15 || (snapshot.timeline.duration ?? 0) >= 20 * 60
    }

    /// The source's own ±15 s when it has one; otherwise a seek, which works
    /// wherever the scrubber does (YouTube ignores the skip commands).
    nonisolated static func skipCommand(forward: Bool, snapshot: NowPlayingSnapshot, at date: Date) -> MediaCommand {
        if snapshot.supportsSkip15 { return forward ? .skipForward15 : .skipBackward15 }
        let target = snapshot.timeline.elapsed(at: date) + (forward ? 15 : -15)
        return .seek(min(max(target, 0), snapshot.timeline.duration ?? .infinity))
    }
}

/// A borderless transport control. Pressing it shows a soft circle, as on
/// the iPhone Live Activity.
struct MediaControlButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 18
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: max(size + 14, 30), height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(MediaPressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct MediaPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.16 : 0))
                    .padding(-2)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
