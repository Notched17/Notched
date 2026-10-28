// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// Controls for island content. Notched is a menu-bar agent that's never the
// active app, so AppKit-backed controls (progress indicators, prominent
// buttons) always draw in their dimmed, inactive look inside the island.
// These are drawn in SwiftUI instead, and look the same whatever is frontmost.

/// A thin rounded progress bar in an activity's accent colour.
struct IslandProgressBar: View {
    /// 0…1.
    let value: Double
    var tint: Color = .white
    var height: CGFloat = 5

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.16))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(height, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: height)
            .accessibilityElement()
            .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

/// A progress bar that follows a time interval on its own, e.g. a timer or
/// a song. It redraws twice a second, and only while it's on screen.
struct IslandTimerProgressBar: View {
    let interval: ClosedRange<Date>
    var countsDown = false
    var tint: Color = .white

    var body: some View {
        TimelineView(.periodic(from: interval.lowerBound, by: 0.5)) { context in
            let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
            let elapsed = context.date.timeIntervalSince(interval.lowerBound)
            let fraction = total > 0 ? min(max(elapsed / total, 0), 1) : 1
            IslandProgressBar(value: countsDown ? 1 - fraction : fraction, tint: tint)
        }
    }
}

/// A capsule button for island content: interactive glass, or a solid
/// accent fill for the one primary action (HIG: at most one per activity).
struct IslandButtonStyle: ButtonStyle {
    enum Kind {
        case glass
        case prominent(Color)
    }

    var kind: Kind = .glass

    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, kind: kind)
    }
}

private struct IslandButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: IslandButtonStyle.Kind
    @Environment(\.islandSurfaceIsGlass) private var onGlass

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.m)
            .frame(minWidth: 28, minHeight: 28)
            .background {
                switch kind {
                case .prominent(let tint): Capsule().fill(tint)
                // Never glass on glass: on a glass island, a quiet fill instead.
                case .glass where onGlass: Capsule().fill(.white.opacity(0.14))
                case .glass: EmptyView()
                }
            }
            .glassEffect(isGlass && !onGlass ? .regular.interactive() : .identity, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }

    private var isGlass: Bool {
        if case .glass = kind { return true }
        return false
    }
}

extension EnvironmentValues {
    /// The island itself is Liquid Glass here, so controls inside it must not
    /// add glass of their own.
    @Entry var islandSurfaceIsGlass = false
}

extension ButtonStyle where Self == IslandButtonStyle {
    static var island: IslandButtonStyle { IslandButtonStyle() }
    static func island(prominent tint: Color) -> IslandButtonStyle { IslandButtonStyle(kind: .prominent(tint)) }
}

/// A rounded tile behind an activity's glyph in the expanded island, its
/// corners concentric with the island's.
struct IslandTile<Content: View>: View {
    var size: CGFloat = 40
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(.white.opacity(0.08), in: ConcentricRectangle(corners: .concentric(minimum: 10), isUniform: true))
    }
}
