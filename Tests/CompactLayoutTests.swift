// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import Notched

/// Compact island and minimal bubble placement (ISLAND-BEHAVIOR.md §3).
/// This Mac's notch is 208 × 37.5 pt at x = 856…1064, hanging from y = 1243.
@Suite("CompactLayout")
struct CompactLayoutTests {
    let notch = NotchGeometry.resolve(NotchGeometryTests.air15)
    let pill = NotchGeometry.resolve(NotchGeometryTests.air15, forcePill: true)

    private func layout(
        _ geometry: NotchGeometry? = nil,
        mode: CompactLayout.Mode = .bubbles,
        primary: CompactLayout.Widths?,
        secondary: CompactLayout.Widths? = nil,
        minimal: [CGFloat] = []
    ) -> CompactLayout {
        CompactLayout.resolve(geometry: geometry ?? notch, mode: mode, primary: primary, secondary: secondary, minimal: minimal)
    }

    @Test("With nothing live the compact island is exactly the notch")
    func idle() {
        let sut = layout(primary: nil)
        #expect(sut.island == CGRect(x: 856, y: 1205.5, width: 208, height: 37.5))
        #expect(sut.bubbles.isEmpty)
        #expect(!sut.isWidthLimited)
    }

    @Test("One activity: both sides get the wider region's width plus padding, so they balance")
    func oneActivityBalanced() {
        let sut = layout(primary: .init(leading: 18, trailing: 40))
        #expect(sut.leadingSide == 60)
        #expect(sut.trailingSide == 60)
        #expect(sut.island == CGRect(x: 796, y: 1205.5, width: 328, height: 37.5))
    }

    @Test("An empty trailing region hides that side of the island")
    func emptyTrailingHides() {
        let sut = layout(primary: .init(leading: 18, trailing: nil))
        #expect(sut.leadingSide == 38)
        #expect(sut.trailingSide == 0)
        #expect(sut.island.minX == 818)
        #expect(sut.island.maxX == 1064)
    }

    @Test("Compact regions are capped at 64 pt each")
    func regionCap() {
        let sut = layout(primary: .init(leading: 120, trailing: 30))
        #expect(sut.leadingSide == 64 + IslandMetrics.compactSlotPadding)
        #expect(sut.trailingSide == sut.leadingSide)
    }

    @Test("Two activities: the second is a trailing bubble 6 pt from the island, and content is width-limited")
    func trailingBubble() throws {
        let sut = layout(primary: .init(leading: 18, trailing: 40), minimal: [20])
        try #require(sut.bubbles.count == 1)
        let bubble = sut.bubbles[0]
        #expect(bubble.minX == sut.island.maxX + 6)
        #expect(bubble.midY == sut.island.midY)
        #expect(sut.isWidthLimited)
    }

    @Test("Three activities: the third is a leading bubble 6 pt from the island")
    func leadingBubble() throws {
        let sut = layout(primary: .init(leading: 18, trailing: 40), minimal: [20, 20])
        try #require(sut.bubbles.count == 2)
        #expect(sut.bubbles[1].maxX == sut.island.minX - 6)
    }

    @Test("Bubbles are circles at least as tall as they are wide, ovals up to 45 pt for wider content")
    func bubbleSizes() throws {
        let sut = layout(primary: .init(leading: 18, trailing: 18), minimal: [4, 80])
        try #require(sut.bubbles.count == 2)
        let height = 37.5 - 2 * IslandMetrics.bubbleInset
        #expect(sut.bubbles[0].size == CGSize(width: height, height: height))
        #expect(sut.bubbles[1].width == 45)
    }

    @Test("Everything together stays within the notch plus 90 pt either side")
    func widthBudget() {
        let sut = layout(primary: .init(leading: 64, trailing: 64), minimal: [40, 40])
        let extent = sut.bubbles.reduce(sut.island) { $0.union($1) }
        #expect(sut.bubbles.count == 2)
        #expect(extent.width <= 208 + 180)
        #expect(sut.leadingSide == sut.trailingSide)
    }

    @Test("Side by side: each activity takes one side of the notch, balanced, with no bubbles for two")
    func sideBySide() {
        let sut = layout(mode: .sideBySide, primary: .init(leading: 16, trailing: 36), secondary: .init(leading: 16, trailing: 20))
        let expected = 16 + IslandMetrics.sideBySideGap + 36 + IslandMetrics.compactSlotPadding
        #expect(sut.leadingSide == expected)
        #expect(sut.trailingSide == expected)
        #expect(sut.bubbles.isEmpty)
        #expect(sut.isWidthLimited)
        #expect(sut.isSideBySide)
    }

    @Test("Side by side: a third activity becomes a trailing bubble within the budget")
    func sideBySideThird() throws {
        let sut = layout(mode: .sideBySide, primary: .init(leading: 30, trailing: 40), secondary: .init(leading: 30, trailing: 40), minimal: [20])
        try #require(sut.bubbles.count == 1)
        #expect(sut.bubbles[0].maxX - sut.island.minX <= 208 + 180)
    }

    @Test("On the pill, bubbles sit beside it, centred on it")
    func pillBubbles() throws {
        let sut = layout(pill, primary: .init(leading: 18, trailing: 40), minimal: [20])
        try #require(sut.bubbles.count == 1)
        #expect(sut.bubbles[0].minX == sut.island.maxX + 6)
        #expect(sut.bubbles[0].midY == sut.island.midY)
        #expect(sut.bubbles[0].height == 32 - 2 * IslandMetrics.bubbleInset)
    }
}
