// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How the island treats the keyboard while a tab that **captures it** (the
/// Terminal, #64) is on screen. Pure, so each rule is tested (ADR-0026).
///
/// The island still never takes keyboard focus on hover, and still hands it
/// back to the user's app on collapse. The differences are only these:
/// - Esc goes to the tab's content (the shell), not to "collapse". ⌘Esc collapses.
/// - ⌘C, ⌘V and ⌘A reach the content, since an agent app has no Edit menu.
/// - Plain arrow keys are the content's, not "previous / next page".
/// - The pointer leaving doesn't collapse the island while the content has
///   keyboard focus, or the user pinned it open.
enum IslandKeyboardPolicy {
    enum EscapeAction: Equatable, Sendable {
        case collapse
        case passToContent
    }

    /// What an Esc key press does. ⌘Esc always collapses.
    static func escape(capturesKeyboard: Bool, command: Bool) -> EscapeAction {
        capturesKeyboard && !command ? .passToContent : .collapse
    }

    /// Whether the pointer leaving should leave the island open.
    static func holdsOpen(capturesKeyboard: Bool, pinned: Bool, hasKeyFocus: Bool) -> Bool {
        capturesKeyboard && (pinned || hasKeyFocus)
    }

    /// When the island loses keyboard focus while a capturing tab is showing
    /// (the user clicked another app): collapse unless pinned or the pointer is still on it.
    static func collapsesAfterLosingFocus(capturesKeyboard: Bool, pinned: Bool, pointerInside: Bool) -> Bool {
        capturesKeyboard && !pinned && !pointerInside
    }

    enum EditCommand: Equatable, Sendable {
        case copy, paste, selectAll
    }

    /// ⌘C, ⌘V and ⌘A for a capturing tab (nil for anything else).
    static func editCommand(characters: String?, command: Bool, control: Bool, shift: Bool, option: Bool, capturesKeyboard: Bool) -> EditCommand? {
        guard capturesKeyboard, command, !control, !shift, !option else { return nil }
        switch characters?.lowercased() {
        case "c": return .copy
        case "v": return .paste
        case "a": return .selectAll
        default: return nil
        }
    }
}
