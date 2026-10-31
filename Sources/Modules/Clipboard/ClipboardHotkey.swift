// SPDX-License-Identifier: GPL-3.0-or-later

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens clipboard history. ⌘⇧V by default; changeable in Settings.
    static let clipboardHistory = Self("clipboardHistory", default: .init(.v, modifiers: [.command, .shift]))
}

/// The one place that talks to KeyboardShortcuts (sindresorhus, MIT), which
/// registers a Carbon hot key: public API, no permission and no event tap.
///
/// The library's own handler is registered once for the life of the app and
/// the shortcut is switched with `enable`/`disable`, which is how its
/// documentation uses it. The module's action sits behind that handler.
/// The log lines (no clipboard content) show how far a key press got.
@MainActor
enum ClipboardHotkey {
    private static var action: (@MainActor () -> Void)?
    private static var isHandlerRegistered = false
    private static let log = Log.module("clipboard")

    static func install(_ action: @escaping @MainActor () -> Void) {
        self.action = action
        if !isHandlerRegistered {
            isHandlerRegistered = true
            KeyboardShortcuts.onKeyUp(for: .clipboardHistory) {
                MainActor.assumeIsolated { ClipboardHotkey.fire() }
            }
        }
        KeyboardShortcuts.enable(.clipboardHistory)
        let shortcut = KeyboardShortcuts.getShortcut(for: .clipboardHistory)
        log.info("Hotkey on: \(shortcut.map { "\($0)" } ?? "no shortcut set", privacy: .public)")
    }

    static func remove() {
        action = nil
        KeyboardShortcuts.disable(.clipboardHistory)
        log.info("Hotkey off")
    }

    private static func fire() {
        log.info("Hotkey pressed (\(action == nil ? "no action" : "opening history"))")
        action?()
    }
}
