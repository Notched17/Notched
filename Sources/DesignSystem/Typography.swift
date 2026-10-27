// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

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
