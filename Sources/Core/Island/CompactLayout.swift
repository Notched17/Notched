// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Where the compact island and its detached minimal bubbles go
/// (ISLAND-BEHAVIOR.md §3). Pure maths on measured content widths, so it is
/// unit-tested; the island view draws it and the controller fits the hover
/// sensors to it.
///
/// - One activity owns both sides of the notch, each as wide as the wider
///   region (balanced, like iPhone), capped at 64 pt. An empty trailing
///   region hides that side.
/// - Bubbles mode: the second activity is a bubble 6 pt right of the island,
///   the third one left of it. Circles, growing into ovals up to 45 pt.
/// - Side by side (iPhone 18 Pro): the first two activities take one side of
///   the notch each; a third becomes a trailing bubble.
/// - Everything together stays within the notch + 90 pt either side; the
///   island's sides shrink to fit. With two or more activities content is
///   width-limited, so modules show their reduced form.
struct CompactLayout: Equatable {
    enum Mode: String, CaseIterable, Codable, Sendable {
        case bubbles
        case sideBySide
    }

    /// One activity's natural compact content widths. A nil trailing width
    /// means it has no trailing region.
    struct Widths: Equatable {
        var leading: CGFloat
        var trailing: CGFloat?
    }

    /// The shape attached to the notch.
    var island: CGRect
    /// How far the island reaches left and right of the notch.
    var leadingSide: CGFloat
    var trailingSide: CGFloat
    /// Minimal bubbles, trailing first, then leading.
    var bubbles: [CGRect]
    var isWidthLimited: Bool
    /// The island's trailing side shows the second activity.
    var isSideBySide: Bool

    static func resolve(geometry: NotchGeometry, mode: Mode, primary: Widths?, secondary: Widths?, minimal: [CGFloat]) -> CompactLayout {
        guard let primary else {
            return CompactLayout(island: geometry.compactRect(leading: 0, trailing: 0), leadingSide: 0, trailingSide: 0,
                                 bubbles: [], isWidthLimited: false, isSideBySide: false)
        }
        let padding = IslandMetrics.compactSlotPadding
        let sideBySide = mode == .sideBySide && secondary != nil
        var leadingSide: CGFloat
        var trailingSide: CGFloat
        if sideBySide, let secondary {
            let side = max(pairWidth(primary), pairWidth(secondary)) + padding
            leadingSide = side
            trailingSide = side
        } else {
            let leading = capped(primary.leading)
            if let trailing = primary.trailing.map(capped) {
                leadingSide = max(leading, trailing) + padding
                trailingSide = leadingSide
            } else {
                leadingSide = leading + padding
                trailingSide = 0
            }
        }

        let base = geometry.compactBaseSize
        let bubbleHeight = base.height - 2 * IslandMetrics.bubbleInset
        let bubbleWidths = minimal.prefix(sideBySide ? 1 : 2).map { width in
            min(max(width + 2 * IslandMetrics.bubblePadding, bubbleHeight), IslandMetrics.bubbleMaxWidth)
        }

        // Shrink the island's sides (keeping them balanced) until everything fits the budget.
        let bubbleSpan = bubbleWidths.reduce(0) { $0 + IslandMetrics.bubbleGap + $1 }
        let excess = base.width + leadingSide + trailingSide + bubbleSpan - (base.width + 2 * IslandMetrics.compactWidthBudget)
        if excess > 0 {
            if trailingSide > 0 {
                leadingSide = floorToPixel(max(leadingSide - excess / 2, 0), scale: geometry.scale)
                trailingSide = leadingSide
            } else {
                leadingSide = floorToPixel(max(leadingSide - excess, 0), scale: geometry.scale)
            }
        }

        let island = geometry.compactRect(leading: leadingSide, trailing: trailingSide)
        var bubbles: [CGRect] = []
        for (index, width) in bubbleWidths.enumerated() {
            let x = index == 0
                ? island.maxX + IslandMetrics.bubbleGap
                : island.minX - IslandMetrics.bubbleGap - width
            let rect = CGRect(x: x, y: island.midY - bubbleHeight / 2, width: width, height: bubbleHeight)
            bubbles.append(NotchGeometry.align(rect, scale: geometry.scale))
        }
        return CompactLayout(island: island, leadingSide: leadingSide, trailingSide: trailingSide, bubbles: bubbles,
                             isWidthLimited: !bubbles.isEmpty || sideBySide, isSideBySide: sideBySide)
    }

    /// Every hit region: the island, then the bubbles.
    var hitRegions: [CGRect] { [island] + bubbles }

    private static func capped(_ width: CGFloat) -> CGFloat {
        min(max(width, 0), IslandMetrics.compactRegionMaxWidth)
    }

    /// Side by side, one activity's leading and trailing content sit together.
    private static func pairWidth(_ widths: Widths) -> CGFloat {
        capped(widths.leading) + (widths.trailing.map { IslandMetrics.sideBySideGap + capped($0) } ?? 0)
    }

    private static func floorToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded(.down) / scale
    }
}
