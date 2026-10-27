// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// How the island reacts to the pointer and how it moves.
struct IslandBehavior: Equatable, Sendable {
    var expandOnHover = true
    var hoverDelay: Duration = .milliseconds(150)
    var animationStyle: AnimationStyle = .smooth
    var hapticsEnabled = true
    /// Click to expand instead of opening the activity (a setting).
    var clickExpands = false
}

/// What the island's own controls ask the rest of the app to do.
@MainActor
struct IslandActions {
    var openSettings: () -> Void = {}
    var pauseIsland: () -> Void = {}
}

/// The island's look: themes per kind of display and the expanded size scale.
struct IslandAppearance: Equatable, Sendable {
    var notchTheme: IslandTheme = .notchBlack
    var pillTheme: IslandTheme = .liquidGlass
    var expandedScale: Double = 1
    var multipleActivities: CompactLayout.Mode = .bubbles
    var keyline = true

    func theme(for kind: NotchGeometry.Kind) -> IslandTheme {
        kind == .notch ? notchTheme : pillTheme
    }
}
