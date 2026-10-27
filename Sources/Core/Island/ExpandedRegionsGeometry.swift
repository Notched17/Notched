// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Places an activity's expanded regions the way the Dynamic Island does
/// (ISLAND-BEHAVIOR.md §4, after WidgetKit's documented algorithm):
///
/// 1. The center region is sized first, keeping the minimum widths of
///    leading and trailing. It sits below the camera housing.
/// 2. Leading and trailing share the remaining width equally. A region no
///    taller than the housing row sits beside the housing (centred in that
///    row) and may use all the room there; a taller one narrows so it can
///    continue down beside the center.
/// 3. The single highest-priority region renders at the full width, in its
///    own row below the others.
/// 4. A leading region marked `belowIfTooWide` drops below the housing when
///    it doesn't fit beside it.
/// 5. Bottom spans the full width below everything.
///
/// Pure maths on sizes, so it is unit-tested; `ExpandedRegionsLayout` is the
/// SwiftUI `Layout` that feeds it real subviews.
struct ExpandedRegionsGeometry {
    enum Role: Hashable, Sendable {
        case leading, trailing, center, bottom
    }

    struct Region {
        var role: Role
        var priority: Double
        var belowIfTooWide: Bool
        /// The narrowest width the region can usefully take.
        var minWidth: CGFloat
        /// The size the region takes when offered a width.
        var size: (CGFloat) -> CGSize

        init(role: Role, priority: Double = 0, belowIfTooWide: Bool = false, minWidth: CGFloat = 0,
             size: @escaping (CGFloat) -> CGSize) {
            self.role = role
            self.priority = priority
            self.belowIfTooWide = belowIfTooWide
            self.minWidth = minWidth
            self.size = size
        }
    }

    /// The width available to the regions.
    var width: CGFloat
    /// The camera housing at the top centre, including its side gaps; `.zero`
    /// for the pill, which has none.
    var housing: CGSize
    var spacing: CGFloat

    func place(_ regions: [Region]) -> (frames: [Role: CGRect], size: CGSize) {
        var byRole: [Role: Region] = [:]
        for region in regions { byRole[region.role] = region }

        let fullWidth = fullWidthRole(byRole)
        let sides = [byRole[.leading], byRole[.trailing]].compactMap { $0 }.filter { $0.role != fullWidth }
        let center = byRole[.center].flatMap { $0.role == fullWidth ? nil : $0 }
        let rowHeight = housing.height
        var frames: [Role: CGRect] = [:]

        // 1. Center first, leaving the sides their minimum width.
        var centerWidth: CGFloat = 0
        if let center {
            let minSide = sides.map(\.minWidth).max() ?? 0
            let proposal = sides.isEmpty ? width : max(width - 2 * (minSide + spacing), 0)
            let size = center.size(proposal)
            centerWidth = min(size.width, proposal)
            frames[.center] = CGRect(x: (width - centerWidth) / 2, y: rowHeight, width: centerWidth, height: size.height)
        }

        // 2. Leading and trailing share what's left, equally.
        let besideHousing = housing.width > 0 ? max((width - housing.width) / 2, 0) : (width - spacing) / 2
        let besideCenter: CGFloat? = center == nil ? nil : max((width - centerWidth) / 2 - spacing, 0)
        for side in sides {
            frames[side.role] = placeSide(side, besideHousing: besideHousing, besideCenter: besideCenter, rowHeight: rowHeight)
        }

        // 3. The highest-priority region gets its own full-width row.
        if let role = fullWidth, let region = byRole[role] {
            let top = max(rowHeight, frames.values.map(\.maxY).max() ?? 0) + (frames.isEmpty ? 0 : spacing)
            frames[role] = CGRect(x: 0, y: top, width: width, height: region.size(width).height)
        }

        // 5. Bottom spans the full width below everything.
        if let bottom = byRole[.bottom] {
            let top = max(rowHeight, frames.values.map(\.maxY).max() ?? 0) + (frames.isEmpty ? 0 : spacing)
            frames[.bottom] = CGRect(x: 0, y: top, width: width, height: bottom.size(width).height)
        }

        let height = max(rowHeight, frames.values.map(\.maxY).max() ?? 0)
        return (frames, CGSize(width: width, height: height))
    }

    private func placeSide(_ side: Region, besideHousing: CGFloat, besideCenter: CGFloat?, rowHeight: CGFloat) -> CGRect {
        let isLeading = side.role == .leading
        // 4. Too wide to sit beside the housing: drop below it.
        if isLeading, side.belowIfTooWide, rowHeight > 0, side.size(.greatestFiniteMagnitude).width > besideHousing {
            // Below the housing it shares the row with the center, if there is one.
            let available = besideCenter ?? width
            let size = side.size(available)
            return CGRect(x: 0, y: rowHeight, width: min(size.width, available), height: size.height)
        }
        var offered = besideHousing
        var size = side.size(offered)
        if rowHeight > 0, size.height > rowHeight {
            // Taller than the housing row: continue down beside the center.
            offered = min(besideHousing, besideCenter ?? besideHousing)
            size = side.size(offered)
        }
        let regionWidth = min(size.width, offered)
        let y = size.height < rowHeight ? (rowHeight - size.height) / 2 : 0
        let x = isLeading ? 0 : width - regionWidth
        return CGRect(x: x, y: y, width: regionWidth, height: size.height)
    }

    /// The one region with a strictly highest positive priority, if any.
    private func fullWidthRole(_ byRole: [Role: Region]) -> Role? {
        let candidates = [Role.leading, .trailing, .center].compactMap { byRole[$0] }
        guard let top = candidates.map(\.priority).max(), top > 0 else { return nil }
        let winners = candidates.filter { $0.priority == top }
        return winners.count == 1 ? winners[0].role : nil
    }
}
