// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Testing
@testable import Notched

@Suite("ExpandedTabs")
struct ExpandedTabsTests {
    private func entry(_ id: String, _ module: String = "m", order: Int = 0) -> TabEntry {
        TabEntry(id: id, moduleID: module, order: order)
    }

    @Test("Tabs sort by order, then by the module catalogue, then by id")
    func ordering() {
        let result = ExpandedTabs.arrange(
            [entry("c", "z", order: 1), entry("b", "a", order: 1), entry("a2", "a", order: 0), entry("a1", "a", order: 0)],
            moduleOrder: ["a", "z"]
        )
        #expect(result.map(\.id) == ["a1", "a2", "b", "c"])
    }

    @Test("A module missing from the catalogue sorts last among equal orders")
    func unknownModuleLast() {
        let result = ExpandedTabs.arrange([entry("x", "unknown"), entry("y", "known")], moduleOrder: ["known"])
        #expect(result.map(\.id) == ["y", "x"])
    }

    @Test("A repeated id keeps the first, and the reserved Island id is dropped")
    func duplicatesAndReserved() {
        let result = ExpandedTabs.arrange(
            [entry("ai", "a"), entry("ai", "b"), entry(ExpandedTabs.islandID, "c")],
            moduleOrder: ["a", "b", "c"]
        )
        #expect(result == [entry("ai", "a")])
    }

    @Test("At most four module tabs are kept, the earliest ones")
    func cap() {
        let entries = (0..<7).map { entry("t\($0)", order: $0) }
        #expect(ExpandedTabs.arrange(entries, moduleOrder: []).map(\.id) == ["t0", "t1", "t2", "t3"])
    }

    @Test("The selection falls back to Island when its tab is gone")
    func selectionFallback() {
        #expect(ExpandedTabs.resolve(selected: "ai", available: ["ai", "term"]) == "ai")
        #expect(ExpandedTabs.resolve(selected: "ai", available: ["term"]) == ExpandedTabs.islandID)
        #expect(ExpandedTabs.resolve(selected: ExpandedTabs.islandID, available: []) == ExpandedTabs.islandID)
    }

    @Test("Stepping wraps around through Island and the module tabs")
    func stepping() {
        let available = ["ai", "term"]
        #expect(ExpandedTabs.step(from: "island", by: 1, available: available) == "ai")
        #expect(ExpandedTabs.step(from: "term", by: 1, available: available) == "island")
        #expect(ExpandedTabs.step(from: "island", by: -1, available: available) == "term")
        #expect(ExpandedTabs.step(from: "gone", by: 1, available: available) == "island")
        #expect(ExpandedTabs.step(from: "island", by: 1, available: []) == "island")
    }

    @Test("⌘1…⌘5 pick a position, and a position without a tab does nothing")
    func shortcutPositions() {
        #expect(ExpandedTabs.id(atPosition: 0, available: ["ai"]) == "island")
        #expect(ExpandedTabs.id(atPosition: 1, available: ["ai"]) == "ai")
        #expect(ExpandedTabs.id(atPosition: 2, available: ["ai"]) == nil)
    }

    @Test("Key presses map to commands, on any layout")
    func keys() {
        func key(_ code: UInt16, _ chars: String? = nil, command: Bool = false, control: Bool = false,
                 shift: Bool = false, option: Bool = false) -> ExpandedKeyCommand? {
            ExpandedTabs.command(keyCode: code, characters: chars, command: command, control: control, shift: shift, option: option)
        }
        #expect(key(18, "1", command: true) == .selectTab(0))
        #expect(key(23, "5", command: true) == .selectTab(4))
        #expect(key(22, "6", command: true) == nil)
        #expect(key(18, "1") == nil)
        #expect(key(48, control: true) == .nextTab)
        #expect(key(48, control: true, shift: true) == .previousTab)
        #expect(key(48) == nil)
        #expect(key(123) == .pageBack)
        #expect(key(124) == .pageForward)
        #expect(key(124, shift: true) == nil)
        #expect(key(124, option: true) == nil)
        #expect(key(18, "1", command: true, option: true) == nil)
    }
}

@Suite("Tab host in the island")
@MainActor
struct IslandTabHostTests {
    private func tab(_ id: String, module: ModuleID = "m", order: Int = 0) -> IslandTab {
        IslandTab(id: id, moduleID: module, title: id.uppercased(), symbol: "star", order: order) { Text(id) }
    }

    private func make() -> (IslandViewModel, ActivityCoordinator) {
        let activities = ActivityCoordinator()
        let model = IslandViewModel(geometry: NotchGeometry.resolve(NotchGeometryTests.air15),
                                    accessibility: AccessibilityOptions(), activities: activities)
        return (model, activities)
    }

    @Test("Without module tabs there is no bar and Island shows")
    func noTabs() {
        let (model, _) = make()
        #expect(!model.showsTabBar)
        #expect(model.selectedModuleTab == nil)
        #expect(model.currentTabID == ExpandedTabs.islandID)
    }

    @Test("A module's tab appears, can be picked, and goes back to Island when the module's tabs are removed")
    func pickAndRemove() {
        let (model, activities) = make()
        activities.setTabs([tab("ai")], from: "m")
        #expect(model.showsTabBar)
        #expect(model.selectTab("ai"))
        #expect(model.selectedModuleTab?.id == "ai")
        #expect(model.expandedActivity == nil)
        #expect(model.expandedPageKey == "tab.ai")
        activities.endAll(from: "m")
        #expect(model.selectedModuleTab == nil)
        #expect(model.currentTabID == ExpandedTabs.islandID)
        #expect(!model.showsTabBar)
    }

    @Test("Picking a tab that doesn't exist, or the one already shown, changes nothing")
    func pickInvalid() {
        let (model, activities) = make()
        activities.setTabs([tab("ai")], from: "m")
        #expect(!model.selectTab("nope"))
        #expect(!model.selectTab(ExpandedTabs.islandID))
    }

    @Test("Keys select and step tabs; arrows page only on the Island tab")
    func keyCommands() {
        let (model, activities) = make()
        activities.setTabs([tab("ai", order: 0), tab("term", module: "n", order: 1)], from: "m")
        activities.setTabs([tab("term", module: "n", order: 1)], from: "n")
        #expect(model.handle(.selectTab(1)))
        #expect(model.currentTabID == "ai")
        #expect(model.handle(.nextTab))
        #expect(model.currentTabID == "term")
        #expect(model.handle(.nextTab))
        #expect(model.currentTabID == ExpandedTabs.islandID)
        #expect(!model.handle(.selectTab(9)))
        _ = model.selectTab("ai")
        #expect(!model.handle(.pageForward))
    }

    @Test("Each module's tabs are replaced independently")
    func independentModules() {
        let (model, activities) = make()
        activities.setTabs([tab("a", module: "m")], from: "m")
        activities.setTabs([tab("b", module: "n")], from: "n")
        activities.setTabs([], from: "m")
        #expect(model.tabs.map(\.id) == ["b"])
    }

    @Test("Hovering or clicking an island region returns to the Island tab")
    func hoverReturnsToIsland() {
        let (model, activities) = make()
        activities.setTabs([tab("ai")], from: "m")
        _ = model.selectTab("ai")
        model.selectPage(for: .island)
        #expect(model.currentTabID == ExpandedTabs.islandID)
    }

    @Test("An alert shows its activity on the Island tab and hides the bar; the pick returns afterwards")
    func alertOverrides() {
        let (model, activities) = make()
        activities.setTabs([tab("ai")], from: "m")
        _ = model.selectTab("ai")
        activities.post(
            LiveActivity(id: "a", moduleID: "x", kind: .live, title: "a", accessibilityLabel: "a", presentation: .text("a")),
            alert: AlertRequest()
        )
        #expect(activities.alert != nil)
        #expect(model.selectedModuleTab == nil)
        #expect(!model.showsTabBar)
        #expect(model.expandedActivity?.id == "a")
        activities.userTookOverAlert()
        #expect(model.selectedTab == "ai")
    }
}
