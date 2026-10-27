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
    /// The expanded island at 100% size.
    static let expandedBase = CGSize(width: 600, height: 190)
    /// Panel padding around the island so shadows aren't clipped. Kept to zero
    /// for the compact notch so the panel never covers anything beside it.
    static let compactNotchPadding: CGFloat = 0
    static let compactPillPadding: CGFloat = NotchGeometry.pillGap
    static let expandedPadding: CGFloat = 20
}
