// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the layout editor (#71) can arrange. Pure data; a test checks these
/// ids against the real modules and tabs so they can't drift.
enum LayoutCatalogue {
    /// Modules whose activities can show beside the notch, so the editor offers
    /// "Show in compact" for them. Banner-only modules (Caps Lock, Network,
    /// Bluetooth, the HUD) and tab-only ones (Clipboard, Reminders, Terminal,
    /// Colour Picker) have nothing to place there.
    static let compactModules: [ModuleID] = [
        "calls", "media", "timers", "keepawake", "downloads", "battery", "sensors", "claudecode", "activityapi", "calendar", "weather",
    ]

    /// Modules whose activities always come first and can't be rearranged or listed-only.
    static let fixedFirst: Set<ModuleID> = ["calls"]

    struct TabInfo: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let symbol: String
        /// The module that adds it, to say what turns it on.
        let moduleName: String
    }

    /// The tabs the app has, in their default order.
    static let knownTabs: [TabInfo] = [
        TabInfo(id: "ai", title: "AI", symbol: "sparkles", moduleName: "Claude Code"),
        TabInfo(id: "today", title: "Today", symbol: "calendar", moduleName: "Calendar, Reminders or Weather"),
        TabInfo(id: "clipboard", title: "Clipboard", symbol: "clipboard", moduleName: "Clipboard"),
        TabInfo(id: "terminal", title: "Terminal", symbol: "terminal", moduleName: "Terminal"),
    ]

    /// The known tabs, then any other tab that exists right now, in the user's order.
    static func editorTabs(live: [TabInfo], layout: TabLayout) -> [TabInfo] {
        let extra = live.filter { tab in !knownTabs.contains { $0.id == tab.id } }
        let all = knownTabs + extra
        let order = layout.arranged(all.map(\.id))
        return order.compactMap { id in all.first { $0.id == id } }
    }
}
