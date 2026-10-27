// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import SwiftUI

// Region views for the Scenario Lab's demo activities. They set the visual
// language later modules follow: SF Pro Rounded, medium weight or heavier,
// one accent colour per activity on black, live data in every presentation,
// and inner shapes concentric with the island.

/// Typography for island content.
enum IslandFont {
    /// Compact values beside the notch.
    static let compact = Font.system(size: 13, weight: .semibold, design: .rounded)
    /// Values inside a minimal bubble.
    static let minimal = Font.system(size: 11, weight: .bold, design: .rounded)
    /// The headline of an expanded activity.
    static let title = Font.system(size: 15, weight: .semibold, design: .rounded)
    /// Secondary lines in the expanded island.
    static let subtitle = Font.system(size: 12, weight: .medium)
    /// A big live value in the expanded island (a countdown, a percentage).
    static let hero = Font.system(size: 30, weight: .semibold, design: .rounded)
}

// MARK: Music

/// Placeholder album art: a warm gradient with a note, in a concentric tile.
struct DemoArtwork: View {
    var size: CGFloat

    var body: some View {
        LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.36), Color(red: 0.62, green: 0.18, blue: 0.62)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// A live level meter: bars that move like music, tinted to the artwork.
struct DemoBars: View {
    var height: CGFloat
    var barWidth: CGFloat = 2.5
    var isPlaying = true
    static let tint = Color(red: 1, green: 0.48, blue: 0.42)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.9) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = time * (5.2 + Double(index) * 1.3) + Double(index) * 1.7
                    let level = isPlaying ? 0.35 + 0.65 * abs(sin(phase) * cos(phase * 0.37)) : 0.2
                    Capsule()
                        .fill(Self.tint)
                        .frame(width: barWidth, height: max(barWidth, height * level))
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }
}

struct DemoMusicExpandedBottom: View {
    let start: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Golden Hour")
                    .font(IslandFont.title)
                Text("Notched Demo · Live Session")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
            }
            IslandTimerProgressBar(interval: start...start.addingTimeInterval(214), tint: .white)
            HStack(spacing: Spacing.xl) {
                Spacer()
                DemoControl(symbol: "backward.fill", label: "Previous")
                DemoControl(symbol: "pause.fill", label: "Pause", size: 18)
                DemoControl(symbol: "forward.fill", label: "Next")
                Spacer()
            }
        }
    }
}

// MARK: Timer

enum DemoTimerStyle {
    static let tint = Color.orange
}

struct DemoCountdown: View {
    let end: Date
    var font: Font = IslandFont.compact

    var body: some View {
        Text(timerInterval: Date.now...max(end, .now), countsDown: true)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(DemoTimerStyle.tint)
            .multilineTextAlignment(.trailing)
    }
}

struct DemoTimerExpandedBottom: View {
    let start: Date
    let end: Date

    var body: some View {
        VStack(spacing: Spacing.m) {
            IslandTimerProgressBar(interval: start...end, countsDown: true, tint: DemoTimerStyle.tint)
            GlassEffectContainer(spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    Button("Pause", systemImage: "pause.fill") {}
                        .buttonStyle(.island)
                    Spacer()
                    Button("Cancel", systemImage: "xmark") {}
                        .buttonStyle(.island)
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
}

struct DemoTimerDone: View {
    var body: some View {
        HStack(spacing: Spacing.m) {
            Button("Stop", systemImage: "stop.fill") {}
                .buttonStyle(.island(prominent: DemoTimerStyle.tint))
            Spacer()
            Button("Repeat", systemImage: "arrow.counterclockwise") {}
                .buttonStyle(.island)
        }
        .labelStyle(.titleAndIcon)
    }
}

// MARK: Call

enum DemoCallStyle {
    static let tint = Color.green
}

struct DemoElapsed: View {
    let start: Date
    var font: Font = IslandFont.compact
    var tint: Color = .white

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(tint)
    }
}

struct DemoAvatar: View {
    var size: CGFloat

    var body: some View {
        Text("SR")
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [.gray.opacity(0.9), .gray.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                        in: Circle())
    }
}

struct DemoCallControls: View {
    var body: some View {
        GlassEffectContainer(spacing: Spacing.m) {
            HStack(spacing: Spacing.l) {
                DemoRoundButton(symbol: "mic.slash.fill", label: "Mute")
                DemoRoundButton(symbol: "speaker.wave.2.fill", label: "Audio Output")
                Spacer()
                Button {
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.island(prominent: .red))
                .accessibilityLabel("End Call")
            }
        }
    }
}

// MARK: Claude Code

enum DemoAgentStyle {
    static let tint = Color(red: 0.85, green: 0.47, blue: 0.34)
}

struct DemoAgentGlyph: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(DemoAgentStyle.tint)
            .symbolEffect(.pulse, options: .repeating)
    }
}

struct DemoAgentDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Claude Code is working…")
                .font(IslandFont.title)
            Label("Editing ActivityCoordinator.swift", systemImage: "pencil.line")
                .font(IslandFont.subtitle)
                .foregroundStyle(.secondary)
            Label("Notched · main", systemImage: "folder")
                .font(IslandFont.subtitle)
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Download

enum DemoDownloadStyle {
    static let tint = Color.blue
}

struct DemoProgressRing: View {
    let progress: Double
    var size: CGFloat
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(DemoDownloadStyle.tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(DemoDownloadStyle.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DemoPercent: View {
    let progress: Double
    var font: Font = IslandFont.compact

    var body: some View {
        Text(progress, format: .percent.precision(.fractionLength(0)))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.white)
    }
}

struct DemoDownloadBottom: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Golden Gate 4K.mov")
                .font(IslandFont.title)
                .lineLimit(1)
            IslandProgressBar(value: progress, tint: DemoDownloadStyle.tint)
            Text(sizeText)
                .font(IslandFont.subtitle)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var sizeText: String {
        let total = 2.9
        let done = total * progress
        let remaining = max(Int((1 - progress) * 140), 0)
        return String(format: "%.1f GB of %.1f GB", done, total) + (remaining > 0 ? " · \(remaining) s left" : "")
    }
}

// MARK: Shared controls

/// A borderless transport control, as on the iPhone Music Live Activity.
struct DemoControl: View {
    let symbol: String
    let label: String
    var size: CGFloat = 15

    var body: some View {
        Button {
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A round button: interactive glass on the black island, a quiet fill on a glass one.
struct DemoRoundButton: View {
    let symbol: String
    let label: String

    var body: some View {
        IslandIconButton(symbol: symbol, label: label, size: 30, onGlassSurface: false) {}
    }
}

/// An expanded leading glyph in a tile concentric with the island's corners.
struct DemoTile<Content: View>: View {
    var size: CGFloat = 40
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(.white.opacity(0.08), in: ConcentricRectangle(corners: .concentric(minimum: 10), isUniform: true))
    }
}
#endif
