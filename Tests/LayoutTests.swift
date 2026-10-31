// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import Testing
@testable import Notched

/// The layout editor's data (#71): the tab layout, "Show in Compact", and the catalogue.
@Suite("TabLayout")
struct TabLayoutTests {
    let all = ["ai", "today", "clipboard", "terminal"]

    @Test("The default layout leaves everything as it is")
    func defaultLayout() {
        #expect(TabLayout.default.arranged(all) == all)
        #expect(!TabLayout.default.isHidden("ai"))
    }

    @Test("Listed tabs come first in the saved order; new ones follow in their own order")
    func arranged() {
        let layout = TabLayout(order: ["terminal", "ai"])
        #expect(layout.arranged(all) == ["terminal", "ai", "today", "clipboard"])
        // A tab saved in the order but not present is skipped, not invented.
        #expect(TabLayout(order: ["gone", "today"]).arranged(all) == ["today", "ai", "clipboard", "terminal"])
    }

    @Test("Moving a tab swaps it along the visible list, stops at the ends, and remembers the whole order")
    func moving() {
        var layout = TabLayout.default
        layout = layout.moving("terminal", by: -1, among: all)
        #expect(layout.arranged(all) == ["ai", "today", "terminal", "clipboard"])
        layout = layout.moving("terminal", by: -9, among: all)
        #expect(layout.arranged(all) == ["terminal", "ai", "today", "clipboard"])
        layout = layout.moving("terminal", by: -1, among: all)
        #expect(layout.arranged(all).first == "terminal")
        layout = layout.moving("clipboard", by: 5, among: all)
        #expect(layout.arranged(all).last == "clipboard")
        #expect(TabLayout.default.moving("nope", by: 1, among: all) == .default)
    }

    @Test("A tab saved in the order but missing now keeps its place at the end when others move")
    func movingKeepsAbsentTabs() {
        let layout = TabLayout(order: ["hello.demo", "ai", "today"]).moving("today", by: -1, among: all)
        #expect(layout.order.contains("hello.demo"))
        #expect(layout.arranged(all).prefix(2) == ["today", "ai"])
    }

    @Test("Dragging, as onMove reports it, moves one tab to a place")
    func dragging() {
        let layout = TabLayout.default.moving(fromOffsets: IndexSet(integer: 3), toOffset: 0, among: all)
        #expect(layout.arranged(all) == ["terminal", "ai", "today", "clipboard"])
        let down = TabLayout.default.moving(fromOffsets: IndexSet(integer: 0), toOffset: 3, among: all)
        #expect(down.arranged(all) == ["today", "clipboard", "ai", "terminal"])
    }

    @Test("Hiding and showing a tab")
    func hiding() {
        var layout = TabLayout.default.setting("ai", visible: false)
        #expect(layout.isHidden("ai"))
        layout = layout.setting("ai", visible: false)
        #expect(layout.hidden == ["ai"])
        layout = layout.setting("ai", visible: true)
        #expect(!layout.isHidden("ai") && layout.hidden.isEmpty)
    }

    @Test("Normalising drops repeats, blanks and the reserved Island tab")
    func normalizing() {
        let layout = TabLayout(order: ["ai", "ai", "", "island", "today"], hidden: ["terminal", "terminal", "island"]).normalized()
        #expect(layout.order == ["ai", "today"])
        #expect(layout.hidden == ["terminal"])
    }

    @Test("Saved layouts load back; damaged ones give the default")
    func saving() {
        let layout = TabLayout(order: ["terminal", "ai"], hidden: ["clipboard"])
        #expect(TabLayout.load(from: layout.encoded()) == layout)
        #expect(TabLayout.load(from: nil) == .default)
        #expect(TabLayout.load(from: Data("nonsense".utf8)) == .default)
    }

    // MARK: Using it

    private func entry(_ id: String, order: Int, module: String = "m") -> TabEntry { TabEntry(id: id, moduleID: module, order: order) }

    @Test("The bar follows the user's order ahead of the tabs' own")
    func userOrderWins() {
        let entries = [entry("ai", order: 10), entry("today", order: 15), entry("clipboard", order: 20), entry("terminal", order: 30)]
        let result = ExpandedTabs.arrange(entries, moduleOrder: [], layout: TabLayout(order: ["terminal", "clipboard"]))
        #expect(result.map(\.id) == ["terminal", "clipboard", "ai", "today"])
    }

    @Test("A hidden tab doesn't take one of the four places, so a fifth can come in")
    func hiddenFreesAPlace() {
        let entries = [entry("a", order: 1), entry("b", order: 2), entry("c", order: 3), entry("d", order: 4), entry("e", order: 5)]
        #expect(ExpandedTabs.arrange(entries, moduleOrder: []).map(\.id) == ["a", "b", "c", "d"])
        let layout = TabLayout(order: [], hidden: ["a"])
        #expect(ExpandedTabs.arrange(entries, moduleOrder: [], layout: layout).map(\.id) == ["b", "c", "d", "e"])
    }

    @Test("Putting a tab first rescues it from the limit")
    func firstRescues() {
        let entries = [entry("a", order: 1), entry("b", order: 2), entry("c", order: 3), entry("d", order: 4), entry("terminal", order: 30)]
        let result = ExpandedTabs.arrange(entries, moduleOrder: [], layout: TabLayout(order: ["terminal"]))
        #expect(result.map(\.id) == ["terminal", "a", "b", "c"])
    }

    @Test("Without a layout the order is exactly what it was before")
    func unchangedWithoutLayout() {
        let entries = [entry("z", order: 2, module: "m2"), entry("y", order: 2, module: "m1"), entry("x", order: 1)]
        #expect(ExpandedTabs.arrange(entries, moduleOrder: ["m1", "m2"]) == ExpandedTabs.arrange(entries, moduleOrder: ["m1", "m2"], layout: .default))
        #expect(ExpandedTabs.arrange(entries, moduleOrder: ["m1", "m2"]).map(\.id) == ["x", "y", "z"])
    }
}

@Suite("Show in Compact")
@MainActor
struct ShowInCompactTests {
    private func coordinator(_ ranking: RankingPolicy = .default) -> ActivityCoordinator {
        let coordinator = ActivityCoordinator()
        var configuration = coordinator.configuration
        configuration.ranking = ranking
        coordinator.configuration = configuration
        return coordinator
    }

    private func post(_ sut: ActivityCoordinator, _ id: String, module: ModuleID, kind: ActivityKind = .live, hideable: Bool = true, relevance: Double = 0) {
        sut.post(LiveActivity(id: ActivityID(id), moduleID: module, kind: kind, title: id, relevance: relevance, isHideable: hideable,
                              accessibilityLabel: id, presentation: .text(id)))
    }

    @Test("Turning a module off for compact keeps its activity out of the notch and the bubbles, but still lists it")
    func listedOnly() {
        let sut = coordinator(RankingPolicy.default.showingInCompact("calendar", false))
        post(sut, "next", module: "calendar", relevance: 99)
        post(sut, "timer", module: "timers")
        #expect(sut.primary?.id == "timer")
        #expect(sut.minimal.isEmpty)
        #expect(sut.visible.map(\.id).contains("next"))
        #expect(sut.live.map(\.id).contains("next"))
    }

    @Test("With only a listed-only activity, nothing is on the island's sides")
    func onlyListed() {
        let sut = coordinator(RankingPolicy.default.showingInCompact("weather", false))
        post(sut, "w", module: "weather", kind: .passive)
        #expect(sut.primary == nil)
        #expect(sut.visible.count == 1)
    }

    @Test("Turning it back on takes effect at once")
    func backOn() {
        let sut = coordinator(RankingPolicy.default.showingInCompact("calendar", false))
        post(sut, "next", module: "calendar")
        #expect(sut.primary == nil)
        var configuration = sut.configuration
        configuration.ranking = RankingPolicy.default.showingInCompact("calendar", false).showingInCompact("calendar", true)
        sut.configuration = configuration
        #expect(sut.primary?.id == "next")
    }

    @Test("An activity that can't be hidden (a call) ignores it")
    func nonHideableIgnores() {
        let sut = coordinator(RankingPolicy.default.showingInCompact("calls", false))
        post(sut, "call", module: "calls", kind: .system, hideable: false)
        #expect(sut.primary?.id == "call")
    }

    @Test("A listed-only activity can't be made the primary one")
    func cannotPromote() {
        let sut = coordinator(RankingPolicy.default.showingInCompact("calendar", false))
        post(sut, "next", module: "calendar")
        post(sut, "timer", module: "timers")
        sut.makePrimary("next")
        #expect(sut.primary?.id == "timer")
    }

    @Test("The choice is kept through the policy's other edits and through saving")
    func policyKeepsIt() {
        let start = RankingPolicy.default.showingInCompact("calendar", false)
        #expect(start.isListedOnly("calendar"))
        #expect(start.pinning("timers").unpinning("timers").isListedOnly("calendar"))
        #expect(start.pinning("timers").pinning("downloads").movingPin("downloads", by: -1).isListedOnly("calendar"))
        #expect(start.moving(.live, by: -1).isListedOnly("calendar"))
        #expect(RankingPolicy.load(from: start.encoded()).isListedOnly("calendar"))
        #expect(!start.showingInCompact("calendar", true).isListedOnly("calendar"))
    }

    @Test("Turning it off twice lists the module once; normalising removes repeats")
    func noRepeats() {
        let twice = RankingPolicy.default.showingInCompact("calendar", false).showingInCompact("calendar", false)
        #expect(twice.listedOnly == ["calendar"])
        #expect(RankingPolicy(order: RankingPolicy.default.order, pinned: [], listedOnly: ["a", "a", "b"]).normalized().listedOnly == ["a", "b"])
    }

    @Test("A policy saved before this existed still loads")
    func oldDataLoads() throws {
        let old = Data(#"{"order":["live","media","passive"],"pinned":["timers"]}"#.utf8)
        let policy = RankingPolicy.load(from: old)
        #expect(policy.order == [.live, .media, .passive])
        #expect(policy.pinned == ["timers"])
        #expect(policy.listedOnly.isEmpty)
        #expect(RankingPolicy.load(from: Data(#"{"pinned":[]}"#.utf8)) == .default)
    }
}

@Suite("Layout catalogue")
@MainActor
struct LayoutCatalogueTests {
    @Test("Every module the editor offers exists")
    func modulesExist() {
        let ids = Set(AppEnvironment.moduleTypes.map { $0.descriptor.id })
        for id in LayoutCatalogue.compactModules { #expect(ids.contains(id), "\(id) is not a module") }
        #expect(LayoutCatalogue.fixedFirst.isSubset(of: Set(LayoutCatalogue.compactModules)))
    }

    @Test("The known tabs use the ids the modules really use")
    func tabIDsMatch() {
        let known = LayoutCatalogue.knownTabs.map(\.id)
        #expect(known.contains(ClaudeCodeModule.tabID))
        #expect(known.contains(TodayHub.tabID))
        #expect(known.contains(ClipboardModule.tabID))
        #expect(known.contains(TerminalModule.tabID))
        #expect(Set(known).count == known.count)
    }

    @Test("The editor lists known tabs, adds any other live tab, and follows the user's order")
    func editorTabs() {
        let extra = LayoutCatalogue.TabInfo(id: "hello.demo", title: "Demo", symbol: "sparkles", moduleName: "Hello")
        let plain = LayoutCatalogue.editorTabs(live: [extra], layout: .default)
        #expect(plain.map(\.id) == ["ai", "today", "clipboard", "terminal", "hello.demo"])
        let ordered = LayoutCatalogue.editorTabs(live: [extra], layout: TabLayout(order: ["terminal", "hello.demo"]))
        #expect(ordered.map(\.id).prefix(2) == ["terminal", "hello.demo"])
        // A live tab that is also a known one isn't listed twice.
        let again = LayoutCatalogue.editorTabs(live: [LayoutCatalogue.knownTabs[0]], layout: .default)
        #expect(again.count == LayoutCatalogue.knownTabs.count)
    }

    @Test("The settings store saves the tab layout and passes it to the island")
    func settingsKeepsLayout() {
        let defaults = UserDefaults(suiteName: "LayoutSettingsTests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.tabLayout = TabLayout(order: ["terminal"], hidden: ["ai"])
        settings.activityRanking = RankingPolicy.default.showingInCompact("weather", false)
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.tabLayout == TabLayout(order: ["terminal"], hidden: ["ai"]))
        #expect(reloaded.activityConfiguration.tabLayout == reloaded.tabLayout)
        #expect(reloaded.activityConfiguration.ranking.isListedOnly("weather"))
    }

    @Test("The island's tab bar uses the layout from the coordinator's settings")
    func islandUsesLayout() {
        let activities = ActivityCoordinator()
        let model = IslandViewModel(geometry: NotchGeometry.resolve(NotchGeometryTests.air15), accessibility: AccessibilityOptions(), activities: activities)
        func tab(_ id: String, order: Int) -> IslandTab { IslandTab(id: id, moduleID: "m", title: id, symbol: "star", order: order) { Text(id) } }
        activities.setTabs((1...5).map { tab("t\($0)", order: $0) }, from: "m")
        #expect(model.tabs.map(\.id) == ["t1", "t2", "t3", "t4"])
        var configuration = activities.configuration
        configuration.tabLayout = TabLayout(order: ["t5"], hidden: ["t1"])
        activities.configuration = configuration
        #expect(model.tabs.map(\.id) == ["t5", "t2", "t3", "t4"])
    }
}
