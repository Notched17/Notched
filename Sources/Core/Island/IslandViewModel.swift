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
        return geometry.panelFrame(for: largest, padding: IslandMetrics.expandedPadding)
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
