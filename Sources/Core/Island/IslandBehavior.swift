// SPDX-License-Identifier: GPL-3.0-or-later

/// How the island reacts to the pointer and how it moves.
struct IslandBehavior: Equatable, Sendable {
    var expandOnHover = true
    var hoverDelay: Duration = .milliseconds(150)
    var animationStyle: AnimationStyle = .smooth
    var hapticsEnabled = true
}

/// What the island's own controls ask the rest of the app to do.
@MainActor
struct IslandActions {
    var openSettings: () -> Void = {}
    var pauseIsland: () -> Void = {}
}
