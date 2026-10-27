// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Which expanded region a subview of `ExpandedRegionsLayout` is.
struct ExpandedRegionTag: LayoutValueKey {
    struct Value: Equatable {
        var role: ExpandedRegionsGeometry.Role
        var priority: Double = 0
        var belowIfTooWide = false
    }

    static let defaultValue = Value(role: .center)
}

/// Lays out an activity's expanded regions around the camera housing with
/// Apple's algorithm (see `ExpandedRegionsGeometry`).
struct ExpandedRegionsLayout: Layout {
    /// The camera housing at the top centre, including its side gaps; `.zero` on the pill.
    var housing: CGSize
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? housing.width + 2 * 120
        return geometry(width).place(regions(subviews)).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = geometry(bounds.width).place(regions(subviews)).frames
        for subview in subviews {
            guard let frame = frames[subview[ExpandedRegionTag.self].role] else { continue }
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func geometry(_ width: CGFloat) -> ExpandedRegionsGeometry {
        ExpandedRegionsGeometry(width: width, housing: housing, spacing: spacing)
    }

    private func regions(_ subviews: Subviews) -> [ExpandedRegionsGeometry.Region] {
        subviews.map { subview in
            let tag = subview[ExpandedRegionTag.self]
            return ExpandedRegionsGeometry.Region(
                role: tag.role,
                priority: tag.priority,
                belowIfTooWide: tag.belowIfTooWide,
                minWidth: subview.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
            ) { width in
                let proposed: CGFloat? = width < 100_000 ? width : nil
                return subview.sizeThatFits(ProposedViewSize(width: proposed, height: nil))
            }
        }
    }
}

/// Hosts a module's region view. The island owns animation, as on iPhone:
/// animations a module starts are dropped, and content changes animate with
/// the island's own short timing (ISLAND-BEHAVIOR.md §5). Numbers roll,
/// and stale content dims.
struct IslandRegionHost<Content: View>: View {
    let revision: Int
    let isStale: Bool
    @ViewBuilder let content: Content
    @Environment(\.islandReduceMotion) private var reduceMotion

    var body: some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .opacity(isStale ? Motion.staleOpacity : 1)
            .animation(reduceMotion ? Motion.reduced : Motion.content, value: revision)
            .animation(reduceMotion ? Motion.reduced : Motion.content, value: isStale)
            // Applied first (outermost): drops whatever animation the update arrived with.
            .transaction { $0.animation = nil }
    }
}

extension EnvironmentValues {
    /// The island's Reduce Motion setting (including the DEBUG override).
    @Entry var islandReduceMotion = false
}
