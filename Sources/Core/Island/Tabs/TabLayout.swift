// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI   // Array.move(fromOffsets:toOffset:), the way onMove reports a drag

/// The user's choice of expanded tabs (#71): which show, and in what order.
/// Pure and saved as JSON.
///
/// Hidden tabs don't count toward the bar's limit of four module tabs, which
/// is what lets the user choose which four to have. A tab that isn't listed in
/// `order` (a module added later) goes after the listed ones in its default order.
struct TabLayout: Equatable, Codable, Sendable {
    static let `default` = TabLayout()

    /// Preferred order, first first. May name tabs that aren't on right now.
    var order: [String] = []
    /// Tabs the user turned off.
    var hidden: [String] = []

    init(order: [String] = [], hidden: [String] = []) {
        self.order = order
        self.hidden = hidden
    }

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }

    func position(of id: String) -> Int? { order.firstIndex(of: id) }

    /// `available` in the user's order: listed tabs first, the rest as given.
    func arranged(_ available: [String]) -> [String] {
        let listed = order.filter(available.contains)
        return listed + available.filter { !listed.contains($0) }
    }

    /// Moves a tab up (negative) or down (positive) among those `available`, stopping at the ends.
    /// Tabs saved in the order but not available now keep their place at the end.
    func moving(_ id: String, by offset: Int, among available: [String]) -> TabLayout {
        var list = arranged(available)
        guard let index = list.firstIndex(of: id) else { return self }
        let target = min(max(index + offset, 0), list.count - 1)
        list.insert(list.remove(at: index), at: target)
        var copy = self
        copy.order = list + order.filter { !list.contains($0) }
        return copy
    }

    /// Moves tabs the way SwiftUI's `onMove` reports it.
    func moving(fromOffsets source: IndexSet, toOffset destination: Int, among available: [String]) -> TabLayout {
        var list = arranged(available)
        list.move(fromOffsets: source, toOffset: destination)
        var copy = self
        copy.order = list + order.filter { !list.contains($0) }
        return copy
    }

    func setting(_ id: String, visible: Bool) -> TabLayout {
        var copy = self
        copy.hidden.removeAll { $0 == id }
        if !visible { copy.hidden.append(id) }
        return copy
    }

    /// No repeats, and never the reserved Island tab.
    func normalized() -> TabLayout {
        func unique(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.filter { $0 != ExpandedTabs.islandID && !$0.isEmpty && seen.insert($0).inserted }
        }
        return TabLayout(order: unique(order), hidden: unique(hidden))
    }

    func encoded() -> Data? { try? JSONEncoder().encode(normalized()) }

    /// What was saved, or the default if there's nothing or it can't be read.
    static func load(from data: Data?) -> TabLayout {
        guard let data, let layout = try? JSONDecoder().decode(TabLayout.self, from: data) else { return .default }
        return layout.normalized()
    }
}
