// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// The Now Playing regions (#9). The reference is the Music Live Activity in
// the iPhone Dynamic Island: artwork leading, a live waveform trailing,
// title and artist under the camera, then the scrubber and the transport
// controls with AirPlay at the end of the row.

/// Album artwork in a continuous-corner square (or a circle in a bubble).
/// A new track blurs in; missing artwork shows a quiet note glyph.
struct MediaArtworkView: View {
    @Environment(\.islandReduceMotion) private var reduceMotion
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
                            .dimmedText(0.7)
                    }
                }
            }
            .id(ArtworkIdentity(track: model.trackKey, hasArtwork: model.artwork != nil))
            .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .opacity))
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

/// Title, then artist and album.
struct MediaTitleBlock: View {
    let model: MediaModel

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot?.title ?? "")
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Text(subtitle(snapshot))
                .font(.system(size: 12))
                .dimmedText(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(_ snapshot: NowPlayingSnapshot?) -> String {
        let parts = [snapshot?.artist, snapshot?.album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (model.sourceName ?? "") : parts.joined(separator: " · ")
    }
}

/// The app playing it, beside the camera housing: its icon and name. Opens the app.
struct MediaSourceLabel: View {
    let model: MediaModel

    var body: some View {
        Button { model.actions.openSource() } label: {
            HStack(spacing: 6) {
                if let icon = model.sourceIcon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                }
                Text(model.sourceName ?? "Now Playing")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(model.sourceName ?? "the app")")
        .accessibilityLabel("Open \(model.sourceName ?? "the app")")
    }
}

/// Where it is playing and the waveform, beside the camera housing's right side.
struct MediaOutputBadge: View {
    let model: MediaModel
    var showsBars: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let output = model.outputs?.current {
                Image(systemName: output.symbol)
                    .font(.system(size: 13))
                    .dimmedText(0.7)
                    .accessibilityLabel("Playing on \(output.name)")
            }
            if showsBars { MediaBarsView(model: model, height: 14, barCount: 4, barWidth: 3) }
        }
    }
}

/// The artwork beside the title, scrubber and controls, tinted from the cover.
struct MediaExpandedBody: View {
    let model: MediaModel
    static let artworkSize: CGFloat = 82

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { model.actions.openSource() } label: {
                MediaArtworkView(model: model, size: Self.artworkSize)
                    // The cover's colour spreads out of all four sides, soft and wide, as on
                    // Spotify: a stronger, tighter glow centred on the cover, and a faint
                    // wide wash that carries on to the right, past the camera housing.
                    .background {
                        if model.artwork != nil, model.showsGlow {
                            ZStack {
                                Ellipse()
                                    .fill(model.tint.opacity(0.265))
                                    .frame(width: 640, height: Self.artworkSize * 2.6)
                                    .blur(radius: 60)
                                    .offset(x: 250)
                                // A bridge between the glow at the cover and the wide wash, so
                                // the colour runs on to the right without a step in it.
                                Ellipse()
                                    .fill(model.tint.opacity(0.22))
                                    .frame(width: 340, height: Self.artworkSize * 2.3)
                                    .blur(radius: 48)
                                    .offset(x: 105)
                                Circle()
                                    .fill(model.tint.opacity(0.345))
                                    .frame(width: Self.artworkSize * 2.2, height: Self.artworkSize * 2.2)
                                    .blur(radius: 34)
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("Open \(model.sourceName ?? "the app")")
            VStack(alignment: .leading, spacing: 0) {
                MediaTitleBlock(model: model)
                Spacer(minLength: 2)
                if let snapshot = model.snapshot {
                    MediaScrubber(timeline: snapshot.timeline, tint: .white) { model.actions.send(.seek($0)) }
                }
                MediaControlsRow(model: model)
            }
            .frame(height: Self.artworkSize)
        }
        // The cover's glow lights the notch's edge, so the title needs a little air below it.
        .padding(.top, IslandMetrics.expandedNotchGap)
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
                MediaPlayButton(isPlaying: model.isPlaying) { model.actions.send(.togglePlayPause) }
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

/// Play or pause: a white circle with a black glyph, the one filled control.
struct MediaPlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(.white, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(MediaPressStyle())
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
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
    @Environment(\.islandReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.16 : 0))
                    .padding(-2)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? Motion.reduced : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
