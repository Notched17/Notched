// SPDX-License-Identifier: GPL-3.0-or-later

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens clipboard history. ⌘⇧V by default; changeable in Settings.
    static let clipboardHistory = Self("clipboardHistory", default: .init(.v, modifiers: [.command, .shift]))
}

/// The one place that talks to KeyboardShortcuts (sindresorhus, MIT), which
/// registers a Carbon hot key: public API, no permission and no event tap.
@MainActor
enum ClipboardHotkey {
    /// Replaces any earlier handler, so turning the setting on twice can't make it fire twice.
    static func install(_ action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.removeAllHandlers()
        KeyboardShortcuts.onKeyUp(for: .clipboardHistory) {
            MainActor.assumeIsolated { action() }
        }
    }

    /// Notched has no other global shortcut, so this removes only the clipboard's.
    static func remove() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
