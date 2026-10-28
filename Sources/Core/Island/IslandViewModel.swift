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

    /// How several activities share the compact island (a setting).
    var multipleActivityMode: CompactLayout.Mode = .bubbles
    /// The keyline setting: a subtle border on bubbles and the expanded island.
    var keylineEnabled = true

    /// Beside a glass pill, bubbles are glass too; beside a notch, black.
    var bubbleStyle: BubbleStyle {
        geometry.kind == .pill && theme.isGlass && !accessibility.reduceTransparency ? .glass : .black
    }

    /// Like iPhone, the keyline only shows when the background is dark, and
    /// never on the compact island attached to the notch (it would outline
    /// the hardware). Glass brings its own edge.
    var showsKeyline: Bool {
        keylineEnabled && accessibility.isDarkAppearance && bubbleStyle == .black
    }

    var showsExpandedKeyline: Bool {
        keylineEnabled && accessibility.isDarkAppearance && presentation == .expanded && !surfaceIsGlass
    }

    // MARK: Compact

    /// One activity's (or a banner's) compact content. Leading and trailing
    /// always come from the same source.
    struct CompactContent {
        /// Identity, and the prefix of its measured widths.
        let key: String
        /// Nil for a banner.
        let activityID: ActivityID?
        let leading: IslandRegion
        let trailing: IslandRegion?
        let accessibilityLabel: String
        let revision: Int
        let isStale: Bool
    }

    /// Everything the compact island shows: a banner pre-empts the primary
    /// activity and the bubbles merge back in; otherwise the primary (and, side
    /// by side, the second activity) plus up to two bubbles.
    struct CompactScene {
        var primary: CompactContent?
        var secondary: CompactContent?
        /// Trailing bubble first, then leading.
        var bubbles: [ActivityRecord] = []
    }

    var compactScene: CompactScene {
        if let banner = activities.banner {
            let content = CompactContent(
                key: "banner.\(banner.id)", activityID: nil, leading: banner.leading, trailing: banner.trailing,
                accessibilityLabel: banner.accessibilityLabel, revision: 0, isStale: false
            )
            return CompactScene(primary: content)
        }
        guard let primary = activities.primary else { return CompactScene() }
        var bubbles = activities.minimal
        var secondary: CompactContent?
        if multipleActivityMode == .sideBySide, !bubbles.isEmpty {
            secondary = compactContent(for: bubbles.removeFirst())
        }
        return CompactScene(primary: compactContent(for: primary), secondary: secondary, bubbles: bubbles)
    }

    private func compactContent(for record: ActivityRecord) -> CompactContent {
        let presentation = record.activity.presentation
        return CompactContent(
            key: record.id.rawValue, activityID: record.id, leading: presentation.compactLeading,
            trailing: presentation.compactTrailing, accessibilityLabel: record.activity.accessibilityLabel,
            revision: record.revision, isStale: record.isStale
        )
    }

    /// Where the compact island and its bubbles go, from the measured widths.
    var compactLayout: CompactLayout {
        let scene = compactScene
        return CompactLayout.resolve(
            geometry: geometry, mode: multipleActivityMode,
            primary: scene.primary.map(compactWidths), secondary: scene.secondary.map(compactWidths),
            minimal: scene.bubbles.map { measuredWidths[Self.minimalKey($0.id)] ?? 0 },
            isBanner: activities.banner != nil
        )
    }

    private func compactWidths(_ content: CompactContent) -> CompactLayout.Widths {
        CompactLayout.Widths(
            leading: measuredWidths["\(content.key).leading"] ?? 0,
            trailing: content.trailing == nil ? nil : measuredWidths["\(content.key).trailing"] ?? 0
        )
    }

    static func minimalKey(_ id: ActivityID) -> String { "\(id.rawValue).minimal" }

    /// Natural widths of compact and minimal regions, measured by the views.
    private(set) var measuredWidths: [String: CGFloat] = [:]

    func reportWidth(_ width: CGFloat, for key: String) {
        let rounded = width.rounded(.up)
        if measuredWidths[key] != rounded { measuredWidths[key] = rounded }
    }

    /// The island rect in global screen coordinates for a presentation.
    func islandRect(for presentation: IslandPresentation) -> CGRect {
        switch presentation {
        case .compact: compactLayout.island
        case .expanded: geometry.expandedRect(size: CGSize(width: expandedWidth, height: expandedHeight))
        }
    }

    /// The island panel never resizes during interaction (ADR-0002): it is
    /// always big enough for the tallest expanded island and the widest
    /// compact island, plus room for the shadow.
    var panelFrame: CGRect {
        let tallest = geometry.expandedRect(size: CGSize(width: expandedWidth, height: maxExpandedHeight))
        let largest = compactLayout.hitRegions.reduce(tallest) { $0.union($1) }
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
        return min(max(measured + expandedTopInset + IslandMetrics.expandedBottomInset, minExpandedHeight), maxExpandedHeight)
    }

    /// The pill has no camera housing row, so its content needs a top margin.
    var expandedTopInset: CGFloat { geometry.kind == .pill && expandedActivity != nil ? Spacing.l : 0 }

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
        switch currentPage {
        case .activity(let id): return activities.live.first { $0.id == id }
        case .home: return nil
        }
    }

    var expandedPageKey: String { expandedActivity.map { "activity.\($0.id)" } ?? "home" }

    // MARK: Pages

    /// A page of the expanded island: one per live activity, then Home.
    enum ExpandedPage: Hashable, Sendable {
        case activity(ActivityID)
        case home
    }

    /// The page the user asked for (by hovering an activity, or paging).
    var selectedPage: ExpandedPage = .home

    /// The Home quick action whose panel is open; closed whenever Home goes away.
    var openHomeAction: String?

    /// Every visible activity in rank order, then Home (ISLAND-BEHAVIOR.md §6).
    var pages: [ExpandedPage] { activities.visible.map { .activity($0.id) } + [.home] }

    /// The selected page, or the primary activity's if the selected one ended.
    var currentPage: ExpandedPage {
        if case .activity(let id) = selectedPage, !activities.visible.contains(where: { $0.id == id }) {
            return activities.primary.map { .activity($0.id) } ?? .home
        }
        return selectedPage
    }

    /// Selects the page an island region leads to: the activity shown there, or Home.
    func selectPage(for target: IslandTarget) {
        switch target {
        case .island:
            selectedPage = activities.banner == nil ? (activities.primary.map { .activity($0.id) } ?? .home) : .home
        case .bubble(let id):
            selectedPage = .activity(id)
        }
    }

    /// Moves to the next (or previous) page, stopping at the ends.
    @discardableResult
    func page(by offset: Int) -> Bool {
        let all = pages
        guard let index = all.firstIndex(of: currentPage) else { return false }
        let next = index + offset
        guard all.indices.contains(next) else { return false }
        selectedPage = all[next]
        return true
    }

    // MARK: Hit regions

    /// What the pointer is on while the island is compact.
    enum IslandTarget: Equatable, Sendable {
        case island
        case bubble(ActivityID)
    }

    /// The compact hit regions with what each one is: the island, then each bubble.
    var compactTargets: [(target: IslandTarget, zone: CGRect)] {
        let layout = compactLayout
        var targets: [(IslandTarget, CGRect)] = [(.island, extendedPastTopEdge(layout.island))]
        for (record, bubble) in zip(compactScene.bubbles, layout.bubbles) {
            targets.append((.bubble(record.id), extendedToTopEdge(bubble)))
        }
        return targets
    }

    /// The compact region under a point, counting every edge as inside.
    func compactTarget(at point: CGPoint) -> IslandTarget? {
        compactTargets.first { Self.contains($0.zone, point) }?.target
    }

    /// A bubble's hot zone reaches up to the top edge, so throwing the pointer
    /// at the top of the screen above it counts.
    private func extendedToTopEdge(_ rect: CGRect) -> CGRect {
        guard geometry.kind == .notch else { return rect }
        var extended = rect
        extended.size.height = geometry.screenFrame.maxY + IslandMetrics.topEdgeOverscan - rect.minY
        return extended
    }

    private static func contains(_ zone: CGRect, _ point: CGPoint) -> Bool {
        point.x >= zone.minX && point.x <= zone.maxX && point.y >= zone.minY && point.y <= zone.maxY
    }

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
        switch presentation {
        case .compact: compactTarget(at: point) != nil
        case .expanded: Self.contains(hotZone(for: .expanded), point)
        }
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

    /// The invisible hover sensor over the compact island.
    var sensorFrame: CGRect { hotZone(for: .compact) }

    /// Sensors over each minimal bubble, trailing first.
    var bubbleSensorFrames: [CGRect] { compactTargets.dropFirst().map(\.zone) }

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
