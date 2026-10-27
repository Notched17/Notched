// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import SwiftUI
import Testing
@testable import Notched

@Suite("IslandViewModel geometry")
@MainActor
struct IslandViewModelTests {
    private func model(forcePill: Bool = false) -> IslandViewModel {
        let geometry = NotchGeometry.resolve(NotchGeometryTests.air15, forcePill: forcePill)
        return IslandViewModel(geometry: geometry, accessibility: AccessibilityOptions(), activities: ActivityCoordinator())
    }

    @Test("On a notch the hover sensor reaches past the top edge, so a pointer pinned to the top row is inside")
    func sensorIncludesTopEdge() {
        let sut = model()
        let compact = sut.islandRect(for: .compact)
        #expect(sut.sensorFrame.minX == compact.minX)
        #expect(sut.sensorFrame.width == compact.width)
        #expect(sut.sensorFrame.minY == compact.minY)
        #expect(sut.sensorFrame.maxY == 1243 + IslandMetrics.topEdgeOverscan)
    }

    @Test("On a notch the expanded hot zone also includes the top edge")
    func expandedHotZoneIncludesTopEdge() {
        let sut = model()
        let expanded = sut.islandRect(for: .expanded)
        #expect(sut.hotZone(for: .expanded).maxY == expanded.maxY + IslandMetrics.topEdgeOverscan)
        #expect(sut.hotZone(for: .expanded).minY == expanded.minY)
    }

    @Test("The island panel extends past the top edge by the same overscan and the island stays put")
    func panelOverscan() {
        let sut = model()
        #expect(sut.panelFrame.maxY == 1243 + IslandMetrics.topEdgeOverscan)
        #expect(sut.topInset == IslandMetrics.topEdgeOverscan)
        sut.presentation = .expanded
        #expect(sut.topInset == IslandMetrics.topEdgeOverscan)
    }

    @Test("A pill below the menu bar needs no overscan: the sensor is exactly the pill")
    func pillHasNoOverscan() {
        let sut = model(forcePill: true)
        #expect(sut.sensorFrame == sut.islandRect(for: .compact))
        #expect(sut.hotZone(for: .expanded) == sut.islandRect(for: .expanded))
    }

    @Test("A pointer pinned to the top row at the notch is still on the island")
    func topRowCountsAsInside() {
        let sut = model()
        #expect(sut.containsPointer(CGPoint(x: 960, y: 1243), for: .compact))
        #expect(sut.containsPointer(CGPoint(x: 856, y: 1243), for: .compact))
        #expect(sut.containsPointer(CGPoint(x: 1064, y: 1243), for: .compact))
        #expect(sut.containsPointer(CGPoint(x: 960, y: 1243), for: .expanded))
    }

    @Test("Pointers beside or below the island are outside it")
    func outsidePoints() {
        let sut = model()
        #expect(!sut.containsPointer(CGPoint(x: 1100, y: 1243), for: .compact))
        #expect(!sut.containsPointer(CGPoint(x: 960, y: 1200), for: .compact))
        #expect(!sut.containsPointer(CGPoint(x: 960, y: 1040), for: .expanded))
        #expect(!sut.containsPointer(CGPoint(x: 1270, y: 1200), for: .expanded))
    }

    // macOS pushes a pointer thrown into the notch back out below the camera
    // housing within ~60 ms (seen in the logs at y ≈ 1185–1203).

    @Test("A quick drop to just below the notch right after entering is a system bounce")
    func bounceBelowNotch() {
        let sut = model()
        #expect(sut.isSystemBounce(exitAt: CGPoint(x: 917, y: 1192), after: .milliseconds(60)))
        #expect(sut.isSystemBounce(exitAt: CGPoint(x: 1026, y: 1196), after: .milliseconds(22)))
    }

    @Test("A slow exit, a sideways exit or a deep drop is a real exit")
    func realExits() {
        let sut = model()
        #expect(!sut.isSystemBounce(exitAt: CGPoint(x: 917, y: 1192), after: .milliseconds(400)))
        #expect(!sut.isSystemBounce(exitAt: CGPoint(x: 1100, y: 1243), after: .milliseconds(30)))
        #expect(!sut.isSystemBounce(exitAt: CGPoint(x: 917, y: 1100), after: .milliseconds(30)))
    }

    @Test("A pill has no camera housing, so it never bounces")
    func pillNeverBounces() {
        let sut = model(forcePill: true)
        let pill = sut.islandRect(for: .compact)
        #expect(!sut.isSystemBounce(exitAt: CGPoint(x: pill.midX, y: pill.minY - 10), after: .milliseconds(30)))
    }

    // Tracking areas never report a pointer that lands exactly on the top row,
    // so a mouse-moved watcher looks for it (seen in the logs at y = 1243).

    @Test("A pointer on the top row within the notch is at the notch's top edge")
    func topEdgeWithinNotch() {
        let sut = model()
        #expect(sut.isOnNotchTopEdge(CGPoint(x: 988.9, y: 1243)))
        #expect(sut.isOnNotchTopEdge(CGPoint(x: 856, y: 1242.5)))
    }

    @Test("Points below the top row, beside the notch, or on a pill are not at the notch's top edge")
    func notTopEdge() {
        #expect(!model().isOnNotchTopEdge(CGPoint(x: 960, y: 1240)))
        #expect(!model().isOnNotchTopEdge(CGPoint(x: 771, y: 1243)))
        #expect(!model(forcePill: true).isOnNotchTopEdge(CGPoint(x: 960, y: 1243)))
    }

    @Test("Compact slots widen the island symmetrically around the notch")
    func compactWidensForSlots() {
        let activities = ActivityCoordinator()
        let sut = IslandViewModel(
            geometry: NotchGeometry.resolve(NotchGeometryTests.air15),
            accessibility: AccessibilityOptions(),
            activities: activities
        )
        #expect(sut.compactSideWidth == 0)
        activities.post(Activity(
            id: "a", moduleID: "m", priority: .liveSession, lifetime: .untilRemoved,
            compactLeading: ActivityContent(width: 24, accessibilityLabel: "a") { EmptyView() },
            compactTrailing: ActivityContent(width: 40, accessibilityLabel: "b") { EmptyView() },
            expanded: nil
        ))
        // The wider slot (40) plus 20 pt of padding on each side of the 208 pt notch.
        #expect(sut.compactSideWidth == 60)
        #expect(sut.islandRect(for: .compact) == CGRect(x: 796, y: 1205.5, width: 328, height: 37.5))
    }
}
