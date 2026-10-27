// SPDX-License-Identifier: GPL-3.0-or-later

/// Whether the island hides on a display showing a fullscreen app (#5).
/// With "Keep showing while media plays" on, an activity that asks to stay
/// (media playing from an app other than the fullscreen one) keeps it.
enum FullscreenVisibility {
    static func shouldHide(isFullscreen: Bool, hideInFullscreen: Bool, keepForMedia: Bool, anyActivityKeepsIsland: Bool) -> Bool {
        guard isFullscreen, hideInFullscreen else { return false }
        return !(keepForMedia && anyActivityKeepsIsland)
    }
}
