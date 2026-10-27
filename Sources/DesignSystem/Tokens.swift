// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Spacing on a 4/8 pt grid.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii for the island shape. All corners are continuous (squircle).
enum Radius {
    /// Concave flare where the compact island meets the top edge of the screen.
    static let compactShoulder: CGFloat = 6
    static let compactBottom: CGFloat = 10
    static let expandedShoulder: CGFloat = 14
    static let expandedBottom: CGFloat = 30
    /// Corners of the expanded pill on screens without a notch.
    static let expandedPill: CGFloat = 30
}

/// Island sizes that don't come from the hardware.
enum IslandMetrics {
    /// Space around compact slot content: the outer margin to the island's
    /// edge plus the inner gap beside the notch.
    static let compactSlotPadding: CGFloat = 20
    /// The inner gap between compact slot content and the notch.
    static let compactSlotInnerGap: CGFloat = 6
    /// The widest a compact region can be (Apple: ~62 pt).
    static let compactRegionMaxWidth: CGFloat = 64
    /// The compact island plus its bubbles never reach further than this past
    /// the notch on either side (on average), so app menus and status items
    /// beside the notch stay usable.
    static let compactWidthBudget: CGFloat = 90
    /// Gap between the island and a detached minimal bubble.
    static let bubbleGap: CGFloat = 6
    /// How far a bubble sits inside the notch row, top and bottom.
    static let bubbleInset: CGFloat = 2
    /// Horizontal padding inside a bubble around its content.
    static let bubblePadding: CGFloat = 6
    /// A bubble grows from a circle into an oval up to this width (Apple: 45 pt).
    static let bubbleMaxWidth: CGFloat = 45
    /// The pill has no camera housing: with an activity live, its two sides
    /// sit together around this small gap (like a Live Activity in the macOS
    /// menu bar).
    static let pillCompactMiddle: CGFloat = 0
    /// Side by side on the pill: the gap (with a hairline divider) between
    /// the two activities, standing in for the camera that separates them on a notch.
    static let pillSideBySideMiddle: CGFloat = 17
    /// Side by side: the gap between one activity's leading and trailing content.
    static let sideBySideGap: CGFloat = 6
    /// Room beside the camera housing on each side of the expanded island,
    /// so a notched Mac gets as much space there as iPhone does (488 pt wide
    /// around a 208 pt notch at 100% size).
    static let expandedSideRoom: CGFloat = 140
    /// The expanded pill's width at 100% size (iPhone's largest expanded width).
    static let expandedPillWidth: CGFloat = 408
    /// The expanded island's content below the housing row, from Apple's
    /// Live Activity dimensions (84–160 pt tall overall).
    static let expandedMinContentHeight: CGFloat = 46
    static let expandedMaxContentHeight: CGFloat = 160
    /// Space between the expanded content and the island's bottom edge.
    static let expandedBottomInset: CGFloat = 16
    /// Panel padding around the expanded island so its shadow isn't clipped.
    static let expandedPadding: CGFloat = 20
    /// How far the notch island's windows reach above the screen's top edge.
    /// A pointer pinned to the top row sits exactly on the edge, which AppKit
    /// counts as outside a window, so hover would flicker without this.
    static let topEdgeOverscan: CGFloat = 2
    /// macOS pushes a pointer thrown into the notch back out below the camera
    /// housing. An exit this close below the notch, this soon after entering,
    /// is that bounce rather than the user leaving.
    static let bounceDepth: CGFloat = 60
    static let bounceWindow: Duration = .milliseconds(250)
}
