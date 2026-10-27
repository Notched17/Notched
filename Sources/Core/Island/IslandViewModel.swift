// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Observation

/// Whether the island is showing its compact or expanded form.
enum IslandPresentation: Equatable, Sendable {
    case compact
    case expanded
}

/// The outline parameters for one state of the island.
struct IslandShapeMetrics: Equatable, Sendable {
    var shoulder: CGFloat
    var top: CGFloat
    var bottom: CGFloat
}

/// Per-island state that the SwiftUI views render. One per display.
@MainActor
@Observable
final class IslandViewModel {
    var geometry: NotchGeometry
    var presentation: IslandPresentation = .compact
    /// Width of the wider compact slot (leading or trailing); 0 when idle.
    var compactSideWidth: CGFloat = 0
    var expandedSize: CGSize = IslandMetrics.expandedBase
    let accessibility: AccessibilityOptions
    @ObservationIgnored var actions = IslandActions()
    /// Called when the island's surface is clicked.
    @ObservationIgnored var onSurfaceTap: () -> Void = {}
    #if DEBUG
    /// Draws a 1 px outline around the island to check pixel alignment.
    var debugOutline = false
    #endif

    init(geometry: NotchGeometry, accessibility: AccessibilityOptions) {
        self.geometry = geometry
        self.accessibility = accessibility
    }

    /// The island rect in global screen coordinates for a presentation.
    func islandRect(for presentation: IslandPresentation) -> CGRect {
        switch presentation {
        case .compact: geometry.compactRect(leadingWidth: compactSideWidth, trailingWidth: compactSideWidth)
        case .expanded: geometry.expandedRect(size: expandedSize)
        }
    }

    /// The island panel never resizes during interaction (ADR-0002): it is
    /// always big enough for the expanded island and the widest compact island,
    /// plus room for the shadow.
    var panelFrame: CGRect {
        let largest = islandRect(for: .expanded).union(islandRect(for: .compact))
        return extendedPastTopEdge(geometry.panelFrame(for: largest, padding: IslandMetrics.expandedPadding))
    }

    /// Where the pointer counts as "on the island" for a presentation.
    func hotZone(for presentation: IslandPresentation) -> CGRect {
        extendedPastTopEdge(islandRect(for: presentation))
    }

    /// Whether a pointer at `point` (screen coordinates) is on the island,
    /// counting every edge as inside. AppKit's tracking areas treat the top
    /// edge of the screen as outside, so a pointer pinned to the top row can
    /// produce false "exited" events; the controller checks them with this.
    func containsPointer(_ point: CGPoint, for presentation: IslandPresentation) -> Bool {
        let zone = hotZone(for: presentation)
        return point.x >= zone.minX && point.x <= zone.maxX && point.y >= zone.minY && point.y <= zone.maxY
    }

    /// Whether an exit from the compact island is macOS pushing a thrown
    /// pointer out from behind the camera housing, rather than the user leaving.
    func isSystemBounce(exitAt point: CGPoint, after elapsed: Duration) -> Bool {
        guard geometry.kind == .notch, elapsed < IslandMetrics.bounceWindow else { return false }
        let compact = islandRect(for: .compact)
        return point.x >= compact.minX && point.x <= compact.maxX
            && point.y < compact.minY && point.y >= compact.minY - IslandMetrics.bounceDepth
    }

    /// Whether the pointer sits on the screen's top pixel row, over the notch.
    /// Tracking areas treat that row as outside, so a pointer that lands there
    /// directly is only seen by the top-edge watcher.
    func isOnNotchTopEdge(_ point: CGPoint) -> Bool {
        guard geometry.kind == .notch else { return false }
        return point.y >= geometry.screenFrame.maxY - 1 && containsPointer(point, for: .compact)
    }

    /// The invisible hover sensor used while compact.
    var sensorFrame: CGRect { hotZone(for: .compact) }

    /// On a notch, reach a little past the top of the screen so the top pixel
    /// row is strictly inside. A pill sits below the menu bar and needs nothing.
    private func extendedPastTopEdge(_ rect: CGRect) -> CGRect {
        guard geometry.kind == .notch else { return rect }
        var extended = rect
        extended.size.height += IslandMetrics.topEdgeOverscan
        return extended
    }

    var islandSize: CGSize { islandRect(for: presentation).size }

    /// Distance from the top of the panel to the top of the island. Constant
    /// per display kind, so resizing the panel never moves the island.
    var topInset: CGFloat {
        let island = islandRect(for: presentation)
        return panelFrame.maxY - island.maxY
    }

    var shapeMetrics: IslandShapeMetrics {
        switch (geometry.kind, presentation) {
        case (.notch, .compact):
            IslandShapeMetrics(shoulder: Radius.compactShoulder, top: 0, bottom: Radius.compactBottom)
        case (.notch, .expanded):
            IslandShapeMetrics(shoulder: Radius.expandedShoulder, top: 0, bottom: Radius.expandedBottom)
        case (.pill, .compact):
            IslandShapeMetrics(shoulder: 0, top: islandSize.height / 2, bottom: islandSize.height / 2)
        case (.pill, .expanded):
            IslandShapeMetrics(shoulder: 0, top: Radius.expandedPill, bottom: Radius.expandedPill)
        }
    }

    // MARK: Expanded layout

    /// Height of the expanded header row. On a notch it matches the notch, so
    /// the header sits beside the camera housing, never under it.
    var headerHeight: CGFloat {
        geometry.kind == .notch ? (geometry.hardwareNotch?.height ?? 38) : 40
    }

    /// Empty space in the middle of the header, reserved for the camera housing.
    var headerNotchGap: CGFloat {
        guard geometry.kind == .notch, let notch = geometry.hardwareNotch else { return 0 }
        return notch.width + 2 * Spacing.s
    }

    /// Horizontal inset of expanded content from the island's edges.
    var contentHorizontalInset: CGFloat {
        geometry.kind == .notch ? Radius.expandedShoulder + Spacing.l : Spacing.xl
    }
}
