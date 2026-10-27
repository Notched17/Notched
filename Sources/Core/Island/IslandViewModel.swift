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
    #if DEBUG
    /// Draws a 1 px outline around the island to check pixel alignment.
    var debugOutline = false
    #endif

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// The island rect in global screen coordinates for a presentation.
    func islandRect(for presentation: IslandPresentation) -> CGRect {
        switch presentation {
        case .compact: geometry.compactRect(leadingWidth: compactSideWidth, trailingWidth: compactSideWidth)
        case .expanded: geometry.expandedRect(size: expandedSize)
        }
    }

    func panelPadding(for presentation: IslandPresentation) -> CGFloat {
        switch (presentation, geometry.kind) {
        case (.expanded, _): IslandMetrics.expandedPadding
        case (.compact, .notch): IslandMetrics.compactNotchPadding
        case (.compact, .pill): IslandMetrics.compactPillPadding
        }
    }

    func panelFrame(for presentation: IslandPresentation) -> CGRect {
        geometry.panelFrame(for: islandRect(for: presentation), padding: panelPadding(for: presentation))
    }

    /// The panel frame big enough for both the current and the target state, so
    /// the island can spring between them without being clipped.
    func panelFrame(spanning from: IslandPresentation, _ to: IslandPresentation) -> CGRect {
        panelFrame(for: from).union(panelFrame(for: to))
    }

    var islandSize: CGSize { islandRect(for: presentation).size }

    /// Distance from the top of the panel to the top of the island. Constant
    /// per display kind, so resizing the panel never moves the island.
    var topInset: CGFloat {
        switch geometry.kind {
        case .notch: 0
        case .pill: NotchGeometry.pillGap
        }
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
}
