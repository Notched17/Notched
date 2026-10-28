// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Detached minimal bubbles beside the compact island (ISLAND-BEHAVIOR.md §3).
/// They're drawn in the island's own panel, so they bud off the island and
/// merge back into it as one continuous motion (ADR-0007).
struct MinimalBubblesView: View {
    let model: IslandViewModel
    /// The island panel's frame, to place bubbles from screen coordinates.
    let panel: CGRect

    var body: some View {
        let layout = model.compactLayout
        // Expanding absorbs the bubbles into the island; collapsing buds them off again.
        let bubbles = model.presentation == .compact ? Array(model.compactScene.bubbles.prefix(layout.bubbles.count)) : []
        ZStack(alignment: .topLeading) {
            ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, record in
                let frame = layout.bubbles[index]
                MinimalBubble(
                    record: record,
                    size: frame.size,
                    style: model.bubbleStyle,
                    showsKeyline: model.showsKeyline
                ) { width in
                    model.reportWidth(width, for: IslandViewModel.minimalKey(record.id))
                }
                .offset(x: frame.minX - panel.minX, y: panel.maxY - frame.maxY)
                .transition(Motion.bud(fromLeading: index == 0, distance: frame.width + IslandMetrics.bubbleGap,
                                       fades: model.bubbleStyle == .glass,
                                       reduceMotion: model.accessibility.reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(model.accessibility.reduceMotion ? Motion.reduced : Motion.budOff, value: bubbles.map(\.id))
        .environment(\.islandCompactWidthLimited, true)
        .environment(\.islandMode, .minimal)
    }
}

/// How bubbles are drawn: black beside the notch, glass beside a glass pill.
enum BubbleStyle: Equatable, Sendable {
    case black
    case glass
}

/// One activity's minimal presentation: a black circle (or oval) with live data.
struct MinimalBubble: View {
    let record: ActivityRecord
    let size: CGSize
    let style: BubbleStyle
    let showsKeyline: Bool
    let onWidth: (CGFloat) -> Void

    var body: some View {
        let shape = Capsule(style: .continuous)
        IslandRegionHost(revision: record.revision, isStale: record.isStale) {
            record.activity.presentation.minimal.view()
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: onWidth)
        .foregroundStyle(.white)
        .frame(width: size.width, height: size.height)
        .background {
            // Glass bubbles get the same dark wash as the glass pill they sit beside.
            shape.fill(.black.opacity(style == .black ? 1 : IslandTheme.glassDarkening))
        }
        .clipShape(shape)
        .glassEffect(style == .glass ? .regular : .identity, in: shape)
        .overlay {
            if showsKeyline {
                shape.strokeBorder((record.activity.keylineTint ?? .white).opacity(0.28), lineWidth: 1)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.activity.accessibilityLabel)
    }
}
