// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the tab host needs to know about a module tab to order it (Foundation
/// only, so the rules below are unit-tested without any views).
struct TabEntry: Equatable, Sendable {
    var id: String
    var moduleID: String
    /// Lower comes first.
    var order: Int
}

/// A key press the expanded island understands.
enum ExpandedKeyCommand: Equatable, Sendable {
    /// ⌘1…⌘5: the tab at this zero-based position (the Island tab is 0).
    case selectTab(Int)
    /// ⌃Tab and ⌃⇧Tab.
    case nextTab
    case previousTab
    /// ← and → page within the Island tab.
    case pageBack
    case pageForward
}

/// The rules of the expanded island's tab bar: the first tab is always
/// "Island" (the activity pages and Home); modules add the rest.
enum ExpandedTabs {
    /// The built-in tab. Module tabs can't use this id.
    static let islandID = "island"
    /// Module tabs beyond this don't fit the island's width.
    static let maxModuleTabs = 4

    /// The module tabs in display order: by `order`, then the module
    /// catalogue's order, then id. A repeated id keeps the first; the
    /// reserved id is dropped; only `maxModuleTabs` are kept.
    static func arrange(_ entries: [TabEntry], moduleOrder: [String], layout: TabLayout = .default) -> [TabEntry] {
        let rank = { (id: String) in moduleOrder.firstIndex(of: id) ?? Int.max }
        // The user's layout first: hidden tabs go (and so don't take one of the four places),
        // listed tabs come in their order, the rest by their own order.
        let sorted = entries
            .filter { $0.id != islandID && !layout.isHidden($0.id) }
            .sorted { (lhs, rhs) in
                (layout.position(of: lhs.id) ?? Int.max, lhs.order, rank(lhs.moduleID), lhs.id)
                    < (layout.position(of: rhs.id) ?? Int.max, rhs.order, rank(rhs.moduleID), rhs.id)
            }
        var seen = Set<String>()
        var result: [TabEntry] = []
        for entry in sorted where seen.insert(entry.id).inserted {
            result.append(entry)
            if result.count == maxModuleTabs { break }
        }
        return result
    }

    /// The tab to show: the selected one, or Island when it's gone (its
    /// module was turned off).
    static func resolve(selected: String, available: [String]) -> String {
        available.contains(selected) ? selected : islandID
    }

    /// The tab `offset` steps from `selected` in `[Island] + available`,
    /// wrapping around. Island when `selected` isn't there.
    static func step(from selected: String, by offset: Int, available: [String]) -> String {
        let all = [islandID] + available
        guard let index = all.firstIndex(of: selected) else { return islandID }
        let count = all.count
        return all[((index + offset) % count + count) % count]
    }

    /// The id for ⌘N's zero-based position, or nil when there's no such tab.
    static func id(atPosition position: Int, available: [String]) -> String? {
        let all = [islandID] + available
        return all.indices.contains(position) ? all[position] : nil
    }

    /// Maps a key press to a command. `characters` is
    /// `charactersIgnoringModifiers`; `keyCode` tells Tab and the arrows
    /// apart from letters on any keyboard layout.
    static func command(keyCode: UInt16, characters: String?, command: Bool, control: Bool, shift: Bool,
                        option: Bool, capturesKeyboard: Bool = false) -> ExpandedKeyCommand? {
        guard !option else { return nil }
        switch keyCode {
        case 48 where control && !command: // Tab
            return shift ? .previousTab : .nextTab
        case 123 where !command && !control && !shift && !capturesKeyboard: // ←
            return .pageBack
        case 124 where !command && !control && !shift && !capturesKeyboard: // →
            return .pageForward
        default:
            guard command, !control, !shift, let digit = characters.flatMap({ Int($0) }), (1...5).contains(digit) else {
                return nil
            }
            return .selectTab(digit - 1)
        }
    }
}
