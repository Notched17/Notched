// SPDX-License-Identifier: GPL-3.0-or-later
//
// The concave top "shoulders" are drawn with quadratic curves, the technique
// used by MrKai77/DynamicNotchKit's NotchShape (MIT). See THIRD_PARTY_NOTICES.md.

import SwiftUI

/// The single, continuously morphing island outline.
///
/// - On a notch it is a body with a flat top flush to the screen edge, concave
///   shoulders that flare into the top edge, and continuous bottom corners.
/// - On a pill it is a continuous rounded rectangle (`shoulderRadius == 0`).
///
/// Every radius is animatable, so compact ↔ expanded is one spring, never a cross-fade.
struct IslandShape: Shape {
    var shoulderRadius: CGFloat
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shoulderRadius, AnimatablePair(topCornerRadius, bottomCornerRadius)) }
        set {
            shoulderRadius = newValue.first
            topCornerRadius = newValue.second.first
            bottomCornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shoulder = max(0, min(shoulderRadius, rect.width / 4, rect.height / 2))
        let body = rect.insetBy(dx: shoulder, dy: 0)
        let limit = max(0, min(body.width, body.height) / 2)
        let top = max(0, min(topCornerRadius, limit))
        let bottom = max(0, min(bottomCornerRadius, limit))
        let bodyPath = UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        ).path(in: body)
        guard shoulder > 0 else { return bodyPath }

        var shoulders = Path()
        // Left flare: from the screen edge, curving down into the body's left side.
        // Each piece overlaps the body so the union has no hairline seam.
        shoulders.move(to: CGPoint(x: rect.minX, y: rect.minY))
        shoulders.addQuadCurve(
            to: CGPoint(x: body.minX, y: rect.minY + shoulder),
            control: CGPoint(x: body.minX, y: rect.minY)
        )
        shoulders.addLine(to: CGPoint(x: body.minX + shoulder, y: rect.minY + shoulder))
        shoulders.addLine(to: CGPoint(x: body.minX + shoulder, y: rect.minY))
        shoulders.closeSubpath()
        // Right flare, mirrored.
        shoulders.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        shoulders.addQuadCurve(
            to: CGPoint(x: body.maxX, y: rect.minY + shoulder),
            control: CGPoint(x: body.maxX, y: rect.minY)
        )
        shoulders.addLine(to: CGPoint(x: body.maxX - shoulder, y: rect.minY + shoulder))
        shoulders.addLine(to: CGPoint(x: body.maxX - shoulder, y: rect.minY))
        shoulders.closeSubpath()
        return bodyPath.union(shoulders)
    }
}

#Preview("Island shapes") {
    VStack(spacing: 24) {
        IslandShape(shoulderRadius: 6, topCornerRadius: 0, bottomCornerRadius: 10)
            .fill(.black).frame(width: 208, height: 37.5)
        IslandShape(shoulderRadius: 14, topCornerRadius: 0, bottomCornerRadius: 30)
            .fill(.black).frame(width: 600, height: 190)
        IslandShape(shoulderRadius: 0, topCornerRadius: 16, bottomCornerRadius: 16)
            .fill(.black).frame(width: 190, height: 32)
    }
    .padding(40)
    .background(.white)
}
