// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A volume or brightness reading as an island banner, in one of the four
/// styles. White on black, springs from the motion tokens, and a plain change
/// under Reduce Motion. The glyph (or ring) sits on the notch's left side, the
/// level and the output's icon on its right.
@MainActor
enum HUDBanner {
    static let duration = Duration.seconds(1.5)

    /// - Parameters:
    ///   - device: the output the volume is for, whose icon follows the level.
    ///   - serial: counts presses, so pushing against a limit nudges the level each time.
    static func make(reading: HUDReading, device: AudioOutputDevice?, serial: Int, style: HUDStyle = .inline) -> TransientBanner {
        let deviceSymbol = device?.symbol
        return TransientBanner(
            id: reading.kind == .volume ? "hud.volume" : "hud.brightness",
            moduleID: HUDModule.descriptor.id,
            leading: IslandRegion { HUDLeadingView(style: style, reading: reading) },
            trailing: hasTrailing(style: style, deviceSymbol: deviceSymbol)
                ? IslandRegion { HUDTrailingView(style: style, reading: reading, deviceSymbol: deviceSymbol, serial: serial) }
                : nil,
            duration: duration,
            priority: .hud,
            accessibilityLabel: label(for: reading)
        )
    }

    /// The ring carries the level on the left, so on the right it has only the output's icon to show.
    static func hasTrailing(style: HUDStyle, deviceSymbol: String?) -> Bool {
        style != .circular || deviceSymbol != nil
    }

    static func label(for reading: HUDReading) -> String {
        let name = reading.kind == .volume ? "Volume" : "Brightness"
        if reading.kind == .volume, reading.isMuted { return "\(name) muted" }
        return "\(name) \(Int((reading.level * 100).rounded())) percent"
    }
}

/// The left side: the glyph, or in the circular style the glyph inside a ring.
struct HUDLeadingView: View {
    let style: HUDStyle
    let reading: HUDReading

    var body: some View {
        if style == .circular {
            HUDRing(reading: reading) { glyph(size: 11) }
        } else {
            glyph(size: BannerMetrics.symbolSize)
        }
    }

    private func glyph(size: CGFloat) -> some View {
        Image(systemName: HUDGlyph.symbol(kind: reading.kind, level: reading.level, isMuted: reading.isMuted))
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// The right side: the level, in the style's shape, and the output's icon.
struct HUDTrailingView: View {
    let style: HUDStyle
    let reading: HUDReading
    let deviceSymbol: String?
    let serial: Int

    var body: some View {
        HStack(spacing: 6) {
            switch style {
            case .inline: HUDBar(reading: reading, serial: serial, length: 44, thickness: 5, axis: .horizontal)
            case .vertical: HUDBar(reading: reading, serial: serial, length: 20, thickness: 5, axis: .vertical)
            case .minimal: HUDBar(reading: reading, serial: serial, length: 40, thickness: 2, axis: .horizontal)
            case .circular: EmptyView()
            }
            if let deviceSymbol, style != .minimal {
                Image(systemName: deviceSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .accessibilityHidden(true)
    }
}

private extension HUDReading {
    /// Empty while muted, as on macOS.
    var shownLevel: Double { isMuted ? 0 : min(1, max(0, level)) }
}

/// A bar that fills as the level rises, along one axis. Pushing against the
/// top or bottom nudges it a little that way.
private struct HUDBar: View {
    let reading: HUDReading
    let serial: Int
    let length: CGFloat
    let thickness: CGFloat
    let axis: Axis
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var track: Color { .white.opacity(contrast == .increased ? 0.5 : 0.28) }
    private var size: CGSize { axis == .horizontal ? CGSize(width: length, height: thickness) : CGSize(width: thickness, height: length) }
    private var fill: CGSize {
        axis == .horizontal ? CGSize(width: length * reading.shownLevel, height: thickness)
                            : CGSize(width: thickness, height: length * reading.shownLevel)
    }

    var body: some View {
        Capsule()
            .fill(track)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: axis == .horizontal ? .leading : .bottom) {
                Capsule()
                    .fill(.white)
                    .frame(width: fill.width, height: fill.height)
                    .animation(reduceMotion ? Motion.reduced : .spring(response: 0.25, dampingFraction: 0.8), value: reading.shownLevel)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: reading.atLimit && !reduceMotion ? serial : 0) { content, offset in
                content.offset(x: axis == .horizontal ? offset : 0, y: axis == .vertical ? offset : 0)
            } keyframes: { _ in
                // Towards the end the level was pushed against: right or up at the top, left or down at the bottom.
                let toward: Double = reading.level >= 0.5 ? 1 : -1
                LinearKeyframe((axis == .horizontal ? toward : -toward) * 4, duration: 0.06)
                SpringKeyframe(0, duration: 0.3, spring: .bouncy)
            }
    }
}

/// The circular style: a ring that fills round, with the glyph inside.
private struct HUDRing<Content: View>: View {
    let reading: HUDReading
    @ViewBuilder let content: Content
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private static var diameter: CGFloat { 24 }
    private static var lineWidth: CGFloat { 2.5 }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(contrast == .increased ? 0.5 : 0.28), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: reading.shownLevel)
                .stroke(.white, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? Motion.reduced : .spring(response: 0.25, dampingFraction: 0.8), value: reading.shownLevel)
            content
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }
}

/// A small black stand-in for the island in Settings, to see a style before choosing it.
struct HUDStylePreview: View {
    let style: HUDStyle
    private static let sample = HUDReading(kind: .volume, targetID: 0, level: 0.6, isMuted: false, atLimit: false)
    private static let device = "laptopcomputer"

    var body: some View {
        HStack(spacing: 0) {
            HUDLeadingView(style: style, reading: Self.sample)
            Spacer(minLength: 56)
            if HUDBanner.hasTrailing(style: style, deviceSymbol: Self.device) {
                HUDTrailingView(style: style, reading: Self.sample, deviceSymbol: Self.device, serial: 0)
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 230, height: 36)
        .background(.black, in: Capsule())
        .accessibilityHidden(true)
    }
}
