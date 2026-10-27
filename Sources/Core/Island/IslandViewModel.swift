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
    /// The Expanded size setting (#72), scaling the expanded island's width.
    var expandedScale: Double = 1
    var theme: IslandTheme = .notchBlack
    let accessibility: AccessibilityOptions
    let activities: ActivityCoordinator
    @ObservationIgnored var actions = IslandActions()
    /// Called when the island's surface is clicked.
    @ObservationIgnored var onSurfaceTap: () -> Void = {}
    #if DEBUG
    /// Draws a 1 px outline around the island to check pixel alignment.
    var debugOutline = false
    #endif

    init(geometry: NotchGeometry, accessibility: AccessibilityOptions, activities: ActivityCoordinator) {
        self.geometry = geometry
        self.accessibility = accessibility
        self.activities = activities
    }

    /// What the compact island shows beside the notch: a banner pre-empts the
    /// primary activity. Leading and trailing always come from the same source.
    struct CompactContent {
        let id: String
        let leading: IslandRegion
        let trailing: IslandRegion?
        let accessibilityLabel: String
    }

    var compactContent: CompactContent? {
        if let banner = activities.banner {
            return CompactContent(id: "banner.\(banner.id)", leading: banner.leading, trailing: banner.trailing,
                                  accessibilityLabel: banner.accessibilityLabel)
        }
        if let primary = activities.primary {
            let presentation = primary.activity.presentation
            return CompactContent(id: primary.id.rawValue, leading: presentation.compactLeading,
                                  trailing: presentation.compactTrailing, accessibilityLabel: primary.activity.accessibilityLabel)
        }
        return nil
    }

    /// The primary activity's update count, so its compact content animates changes.
    var compactRevision: Int { activities.banner == nil ? activities.primary?.revision ?? 0 : 0 }
    var compactIsStale: Bool { activities.banner == nil && activities.primary?.isStale == true }

    /// The widest compact region's natural width, measured by the view.
    var measuredCompactWidth: CGFloat = 0
    @ObservationIgnored private var compactWidths: (id: String, leading: CGFloat, trailing: CGFloat)?

    /// Called by the compact view with each region's natural width.
    func reportCompactWidth(_ width: CGFloat, for id: String, leading: Bool) {
        var widths = compactWidths?.id == id ? compactWidths! : (id: id, leading: 0, trailing: 0)
        if leading { widths.leading = width } else { widths.trailing = width }
        compactWidths = widths
        let widest = max(widths.leading, widths.trailing).rounded(.up)
        if measuredCompactWidth != widest { measuredCompactWidth = widest }
    }

    /// How far the compact island grows on each side to fit its content; 0 when idle.
    var compactSideWidth: CGFloat {
        guard compactContent != nil, measuredCompactWidth > 0 else { return 0 }
        return measuredCompactWidth + IslandMetrics.compactSlotPadding
    }

    /// The island rect in global screen coordinates for a presentation.
    func islandRect(for presentation: IslandPresentation) -> CGRect {
        switch presentation {
        case .compact: geometry.compactRect(leadingWidth: compactSideWidth, trailingWidth: compactSideWidth)
        case .expanded: geometry.expandedRect(size: CGSize(width: expandedWidth, height: expandedHeight))
        }
    }

    /// The island panel never resizes during interaction (ADR-0002): it is
    /// always big enough for the tallest expanded island and the widest
    /// compact island, plus room for the shadow.
    var panelFrame: CGRect {
        let tallest = geometry.expandedRect(size: CGSize(width: expandedWidth, height: maxExpandedHeight))
        let largest = tallest.union(islandRect(for: .compact))
        return extendedPastTopEdge(geometry.panelFrame(for: largest, padding: IslandMetrics.expandedPadding))
    }

    // MARK: Expanded size

    /// Wide enough to give the regions beside the camera housing as much room
    /// as iPhone does; the pill uses iPhone's largest expanded width.
    var expandedWidth: CGFloat {
        let base: CGFloat = if geometry.kind == .notch, let notch = geometry.hardwareNotch {
            notch.width + 2 * IslandMetrics.expandedSideRoom
        } else {
            IslandMetrics.expandedPillWidth
        }
        return (base * expandedScale).rounded()
    }

    /// The expanded island's height follows its content, between Apple's
    /// minimum and maximum (taller content is truncated).
    var expandedHeight: CGFloat {
        let measured = expandedPageHeights[expandedPageKey] ?? 0
        return min(max(measured + IslandMetrics.expandedBottomInset, minExpandedHeight), maxExpandedHeight)
    }

    var minExpandedHeight: CGFloat { headerHeight + IslandMetrics.expandedMinContentHeight }
    var maxExpandedHeight: CGFloat { headerHeight + IslandMetrics.expandedMaxContentHeight }

    /// Measured content height of each expanded page, so a page that was shown
    /// before opens at the right size straight away.
    var expandedPageHeights: [String: CGFloat] = [:]

    func reportExpandedHeight(_ height: CGFloat, for page: String) {
        let rounded = height.rounded(.up)
        if expandedPageHeights[page] != rounded { expandedPageHeights[page] = rounded }
    }

    /// The activity the expanded island shows: the alerting one, else the primary.
    var expandedActivity: ActivityRecord? {
        if let alert = activities.alert, let record = activities.live.first(where: { $0.id == alert.activityID }) {
            return record
        }
        return activities.primary
    }

    var expandedPageKey: String { expandedActivity.map { "activity.\($0.id)" } ?? "home" }

    /// The camera housing the expanded regions wrap around: the notch plus a
    /// small gap each side. The pill has none.
    var housingSize: CGSize {
        guard geometry.kind == .notch else { return .zero }
        return CGSize(width: headerNotchGap, height: headerHeight)
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

    // MARK: Theme

    /// Whether the theme shows in the current state. On a notch the compact
    /// island always stays black, so it merges with the hardware.
    var showsTheme: Bool {
        geometry.kind == .pill || presentation == .expanded
    }

    /// Whether the island is currently drawn as glass.
    var surfaceIsGlass: Bool {
        showsTheme && theme.isGlass && !accessibility.reduceTransparency
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
