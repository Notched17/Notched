// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// Where a module's section sits on the Today tab.
enum TodaySlot: Hashable, Sendable {
    /// A strip across the top (weather).
    case header
    /// The left column (calendar).
    case leading
    /// The right column (reminders).
    case trailing
}

/// One module's part of the Today tab. The modules stay separate: each has
/// its own toggle, permission and settings, and only the tab is shared.
@MainActor
struct TodaySection: Identifiable {
    let id: String
    let moduleID: ModuleID
    let slot: TodaySlot
    let content: IslandRegion
}

/// How the Today tab divides its space, given which slots have a section.
/// Pure so it can be tested; the view only follows it.
struct TodayLayout: Equatable, Sendable {
    var hasHeader: Bool
    /// The columns present, left to right. One column takes the full width.
    var columns: [TodaySlot]
    /// How many rows a column may show: the header takes the height of one.
    var rowLimit: Int

    static func make(slots: Set<TodaySlot>) -> TodayLayout {
        let hasHeader = slots.contains(.header)
        let columns = [TodaySlot.leading, .trailing].filter(slots.contains)
        return TodayLayout(hasHeader: hasHeader, columns: columns, rowLimit: hasHeader && !columns.isEmpty ? 2 : 3)
    }
}

/// Collects the sections modules offer and publishes them as one "Today" tab,
/// which exists only while at least one section does. The tab belongs to the
/// hub, not to a module, so it is removed when the last section goes
/// (`remove(moduleID:)` from each module's `stop()`).
@MainActor
@Observable
final class TodayHub {
    static let tabID = "today"
    static let pseudoModuleID = ModuleID("today")

    private(set) var sections: [TodaySection] = []
    /// Connected by the app to the coordinator's `setTabs`; does nothing in tests.
    @ObservationIgnored var publishTabs: ([IslandTab]) -> Void = { _ in }

    /// Adds a section, or replaces the one with the same id.
    func set(_ section: TodaySection) {
        sections.removeAll { $0.id == section.id }
        sections.append(section)
        publish()
    }

    /// Takes away every section a module offered.
    func remove(moduleID: ModuleID) {
        let before = sections.count
        sections.removeAll { $0.moduleID == moduleID }
        if sections.count != before { publish() }
    }

    func sections(in slot: TodaySlot) -> [TodaySection] {
        sections.filter { $0.slot == slot }
    }

    var layout: TodayLayout { TodayLayout.make(slots: Set(sections.map(\.slot))) }

    private func publish() {
        guard !sections.isEmpty else { publishTabs([]); return }
        let hub = self
        publishTabs([IslandTab(
            id: Self.tabID, moduleID: Self.pseudoModuleID, title: "Today", symbol: "calendar",
            accessibilityLabel: "Today", order: 15
        ) { TodayTabView(hub: hub) }])
    }
}

extension EnvironmentValues {
    /// How many rows a Today section may show (it depends on the header).
    @Entry var todayRowLimit = 3
    /// True when the weather strip shares the tab with the Calendar and Reminders columns, so it shows fewer hours.
    @Entry var todayHasColumns = false
}

/// The Today tab (spec §3.1): a header strip, then up to two columns.
struct TodayTabView: View {
    let hub: TodayHub

    var body: some View {
        let layout = hub.layout
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(hub.sections(in: .header)) { $0.content.view() }
            if !layout.columns.isEmpty {
                HStack(alignment: .top, spacing: Spacing.m) {
                    ForEach(layout.columns, id: \.self) { slot in
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            ForEach(hub.sections(in: slot)) { $0.content.view() }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .environment(\.todayRowLimit, layout.rowLimit)
        .environment(\.todayHasColumns, !layout.columns.isEmpty)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
