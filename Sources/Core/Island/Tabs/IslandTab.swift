// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A tab a module adds to the expanded island, such as "AI". The tab bar
/// appears only while at least one module offers a tab; the built-in Island
/// tab (activities and Home) is always first.
@MainActor
struct IslandTab: Identifiable {
    /// Unique across modules; "island" is reserved.
    let id: String
    let moduleID: ModuleID
    var title: String
    var symbol: String
    /// Read by VoiceOver in place of the title, e.g. "Claude Code usage".
    var accessibilityLabel: String
    /// Lower comes first; ties follow the module catalogue.
    var order: Int = 0
    /// Built only while the tab is selected.
    let content: IslandRegion
    /// Called with true when the tab appears and false when it goes, so a
    /// module can register refreshes with `RefreshScheduler.setUIVisible`
    /// only while it's on screen.
    var onVisibilityChange: (@MainActor (Bool) -> Void)?

    init(id: String, moduleID: ModuleID, title: String, symbol: String, accessibilityLabel: String? = nil,
         order: Int = 0, onVisibilityChange: (@MainActor (Bool) -> Void)? = nil,
         @ViewBuilder content: @escaping () -> some View) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel ?? title
        self.order = order
        self.onVisibilityChange = onVisibilityChange
        self.content = IslandRegion(content)
    }

    var entry: TabEntry { TabEntry(id: id, moduleID: moduleID.rawValue, order: order) }
}
