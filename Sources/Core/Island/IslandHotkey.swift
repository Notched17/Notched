// SPDX-License-Identifier: GPL-3.0-or-later

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the island from the keyboard (accessibility: the island otherwise
    /// opens only on hover or a click). No default: the user picks one in
    /// Settings ▸ General, and nothing is registered until they do.
    static let openIsland = Self("openIsland")
}

/// The one place that registers the Open Island shortcut: a Carbon hot key
/// (public API, no permission, no event tap), same as the clipboard hotkey.
@MainActor
enum IslandHotkey {
    private static var isHandlerRegistered = false

    /// Call once at launch. With no shortcut set this costs nothing.
    static func install(_ action: @escaping @MainActor () -> Void) {
        guard !isHandlerRegistered else { return }
        isHandlerRegistered = true
        KeyboardShortcuts.onKeyUp(for: .openIsland) { MainActor.assumeIsolated { action() } }
    }
}
