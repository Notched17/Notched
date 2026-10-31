// SPDX-License-Identifier: GPL-3.0-or-later

/// Lets a module ask the islands to do something on its behalf, such as
/// opening on its tab from a hotkey. The app connects it once the islands
/// exist; until then (and in tests) every call does nothing.
@MainActor
final class IslandCommands {
    /// Expands every island onto the module tab with this id. With `focus`,
    /// the panel also takes keyboard focus, so a search field can be typed in.
    var showTab: (_ id: String, _ focus: Bool) -> Void = { _, _ in }
    /// Collapses every island, e.g. after an item was copied back.
    var collapse: () -> Void = {}
    /// Gives the island under the pointer keyboard focus, after a click inside
    /// a view that takes keys itself (the Terminal). Never called on hover.
    var requestKeyFocus: () -> Void = {}
}
