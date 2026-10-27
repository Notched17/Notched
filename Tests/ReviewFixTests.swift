// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing
@testable import DynamicNotch

@Suite("Review fixes", .serialized)
@MainActor
struct ReviewFixTests {
    private func makeController() -> IslandController {
        IslandController(
            displayID: "TEST",
            geometry: NotchGeometry.resolve(NotchGeometryTests.air15),
            behavior: IslandBehavior(expandOnHover: true, hoverDelay: .zero, animationStyle: .smooth, hapticsEnabled: false),
            accessibility: AccessibilityOptions(),
            activities: ActivityCoordinator(),
            actions: IslandActions()
        )
    }

    @Test("A visible island expands when the pointer reaches the notch's top edge")
    func visibleIslandExpandsAtTopEdge() {
        let controller = makeController()
        defer { controller.tearDown() }
        controller.pointerMoved(to: CGPoint(x: 960, y: 1243))
        #expect(controller.model.presentation == .expanded)
    }

    @Test("A paused or fullscreen-hidden island ignores the pointer at the top edge")
    func hiddenIslandIgnoresPointer() {
        let controller = makeController()
        defer { controller.tearDown() }
        controller.setHidden(true)
        controller.pointerMoved(to: CGPoint(x: 960, y: 1243))
        #expect(controller.model.presentation == .compact)
    }

    final class Counter { var value = 0 }

    @Test("Observers are removed when their tokens are released")
    func tokensRemoveObserversOnRelease() {
        let counter = Counter()
        let name = Notification.Name("me.rkck.DynamicNotch.tests.\(UUID().uuidString)")
        var tokens: NotificationTokens? = NotificationTokens()
        tokens?.observe(name) { counter.value += 1 }
        NotificationCenter.default.post(name: name, object: nil)
        #expect(counter.value == 1)
        tokens = nil
        NotificationCenter.default.post(name: name, object: nil)
        #expect(counter.value == 1)
    }
}
