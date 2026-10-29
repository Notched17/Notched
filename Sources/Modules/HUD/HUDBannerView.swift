// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A volume or brightness reading as an island banner: the inline style,
/// like the iPhone's. The glyph sits beside the notch's left, a slim level
/// bar and the output's icon on its right. White on black, springs from the
/// motion tokens, a plain change under Reduce Motion.
@MainActor
enum HUDBanner {
    static let duration = Duration.seconds(1.5)

    /// - Parameters:
    ///   - device: the output the volume is for, whose icon follows the bar.
    ///   - serial: counts presses, so pushing against a limit nudges the bar each time.
    static func make(reading: HUDReading, device: AudioOutputDevice?, serial: Int) -> TransientBanner {
        TransientBanner(
            id: reading.kind == .volume ? "hud.volume" : "hud.brightness",
            moduleID: HUDModule.descriptor.id,
            leading: IslandRegion { HUDGlyphView(reading: reading) },
            trailing: IslandRegion { HUDLevelView(reading: reading, deviceSymbol: device?.symbol, serial: serial) },
            duration: duration,
            priority: .hud,
            accessibilityLabel: label(for: reading)
        )
    }

    static func label(for reading: HUDReading) -> String {
        let name = reading.kind == .volume ? "Volume" : "Brightness"
        if reading.kind == .volume, reading.isMuted { return "\(name) muted" }
        return "\(name) \(Int((reading.level * 100).rounded())) percent"
    }
}

private struct HUDGlyphView: View {
    let reading: HUDReading

    var body: some View {
        Image(systemName: HUDGlyph.symbol(kind: reading.kind, level: reading.level, isMuted: reading.isMuted))
            .font(.system(size: BannerMetrics.symbolSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

private struct HUDLevelView: View {
    let reading: HUDReading
    let deviceSymbol: String?
    let serial: Int
    @Environment(\.islandReduceMotion) private var reduceMotion

    private static let barWidth: CGFloat = 44
    private static let barHeight: CGFloat = 5

    /// Empty while muted, as on macOS.
    private var shownLevel: Double { reading.isMuted ? 0 : min(1, max(0, reading.level)) }

    var body: some View {
        HStack(spacing: 6) {
            bar
            if let deviceSymbol {
                Image(systemName: deviceSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .accessibilityHidden(true)
    }

    private var bar: some View {
        Capsule()
            .fill(.white.opacity(0.28))
            .frame(width: Self.barWidth, height: Self.barHeight)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .frame(width: Self.barWidth * shownLevel, height: Self.barHeight)
                    .animation(reduceMotion ? Motion.reduced : .spring(response: 0.25, dampingFraction: 0.8), value: shownLevel)
            }
            // Pushing against the top or bottom nudges the bar a little that way.
            .keyframeAnimator(initialValue: 0.0, trigger: reading.atLimit && !reduceMotion ? serial : 0) { content, offset in
                content.offset(x: offset)
            } keyframes: { _ in
                LinearKeyframe(reading.level >= 0.5 ? 4 : -4, duration: 0.06)
                SpringKeyframe(0, duration: 0.3, spring: .bouncy)
            }
    }
}
